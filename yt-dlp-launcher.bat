<# :
@echo off
setlocal
set "YTDL_SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ([IO.File]::ReadAllText($env:YTDL_SELF, [Text.Encoding]::UTF8))"
exit /b %errorlevel%
#>

# =====================================================================
#  yt-dlp ランチャー
#  ダブルクリックで起動 → URL をコピーして Enter を押すだけでダウンロード
#
#  先頭の <# : ～ #> は cmd 用の起動部分（PowerShell からはコメント扱い）。
#  cmd はそこで自分自身を PowerShell に渡して終了し、以降を PowerShell が実行する。
#  cmd 部分を壊さないよう、このファイルは BOM なし UTF-8 で保存すること。
# =====================================================================

# ===== 設定 =====
# 設定はこの .bat と同じフォルダの yt-dlp-launcher.json に保存する（初回起動時に作成）。
# .bat を新しい版に差し替えても設定は残る。[m][c][p] で切り替えた状態も保存される。
#   OutDir        : 保存先。空ならデスクトップ（OneDrive にリダイレクトされていても正しく解決される）
#                   %USERPROFILE% などの環境変数も使える。JSON なので \ は \\ と書くか / を使う
#   CookieBrowser : cookie を読むブラウザ（firefox 推奨。Windows 版 Chrome は暗号化の変更で読めないことが多い）
#   TitleBytes    : ファイル名のタイトル部分の上限（バイト）。Windows のファイル名長制限対策
#   Mode          : ダウンロードモード（下の $Modes のキー）
#   Cookies       : cookie を使うか（true / false）
#   Playlist      : 再生リストを全部落とすか（true / false）
$Defaults = [ordered]@{
    OutDir        = ''
    CookieBrowser = 'firefox'
    TitleBytes    = 80
    Mode          = '1'
    Cookies       = $false
    Playlist      = $false
}

# ===== ダウンロードモード =====
$Modes = [ordered]@{
    '1' = @{ Name = '最高画質 (mkv)';                Args = @('-f', 'bv*+ba/b', '--merge-output-format', 'mkv') }
    '2' = @{ Name = '互換性重視 (mp4 / H.264+AAC)';  Args = @('-S', 'vcodec:h264,res,acodec:aac', '--merge-output-format', 'mp4') }
    '3' = @{ Name = '音声のみ (mp3)';                Args = @('-x', '--audio-format', 'mp3', '--audio-quality', '0') }
    '4' = @{ Name = '音声のみ (元の形式・無変換)';   Args = @('-x', '--audio-format', 'best') }
}

$ErrorActionPreference = 'Continue'

# この .bat のあるフォルダ
$SelfDir = if ($env:YTDL_SELF) { Split-Path -Parent $env:YTDL_SELF } else { (Get-Location).Path }

# この .bat と同じフォルダを PATH の先頭に追加（yt-dlp.exe 等を同じフォルダに置くだけでも動くように）
$env:Path = $SelfDir + ';' + $env:Path

$ConfigPath = Join-Path $SelfDir 'yt-dlp-launcher.json'

# ===== 実行時の状態 =====
$State = @{
    # このセッションでダウンロードに成功した URL（クリップボードの URL を二重に処理しないため）
    Done = New-Object 'System.Collections.Generic.HashSet[string]'
}
$Host.UI.RawUI.WindowTitle = 'yt-dlp ランチャー'

# ---------------------------------------------------------------------
# 共通関数
# ---------------------------------------------------------------------

# PATH を再読み込み（winget でインストールした直後に反映させるため）
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$SelfDir;$machine;$user"
}

function Test-Command([string]$Name) {
    return [bool](Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue)
}

# コマンドの実体のフルパス（見つからなければ $null）
function Get-CommandSource([string]$Name) {
    $c = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source } else { return $null }
}

# そのファイルがこの .bat と同じフォルダにあるか
function Test-InSelfDir([string]$Path) {
    $dir = [IO.Path]::GetFullPath((Split-Path -Parent $Path)).TrimEnd('\')
    $self = [IO.Path]::GetFullPath($SelfDir).TrimEnd('\')
    return [string]::Equals($dir, $self, [StringComparison]::OrdinalIgnoreCase)
}

# 引数配列を Windows のコマンドライン文字列に変換（空白や " を含む引数を正しくクォート）
function ConvertTo-ArgString([string[]]$ArgList) {
    $quoted = foreach ($a in $ArgList) {
        if ($a -eq '') {
            '""'
        } elseif ($a -notmatch '[\s"]') {
            $a
        } else {
            '"' + (($a -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
        }
    }
    return ($quoted -join ' ')
}

# 外部コマンドをこのコンソールで直接実行し、終了コードを返す
# （PowerShell のパイプラインを通さないので、進捗バーがそのまま表示される）
function Invoke-Native([string]$Name, [string[]]$ArgList) {
    $exe = (Get-Command $Name -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = ConvertTo-ArgString $ArgList
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.WaitForExit()
    return $p.ExitCode
}

function Write-Info([string]$Text) { Write-Host $Text -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host $Text -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host $Text -ForegroundColor Yellow }
function Write-Err([string]$Text)  { Write-Host $Text -ForegroundColor Red }

# 設定ファイルを読み込む（無ければ既定値で作成）。足りない項目・おかしな値は既定値で補う
function Import-Config {
    $cfg = [ordered]@{}
    foreach ($k in $Defaults.Keys) { $cfg[$k] = $Defaults[$k] }

    $script:ConfigReadOnly = $false
    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            $json = [IO.File]::ReadAllText($ConfigPath, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
            foreach ($p in $json.PSObject.Properties) {
                if ($cfg.Contains($p.Name) -and $null -ne $p.Value) { $cfg[$p.Name] = $p.Value }
            }
        } catch {
            # 書き損じた設定ファイルを上書きして消さないよう、このセッションでは保存しない
            Write-Warn ("設定ファイルを読めませんでした。既定値で起動し、設定は保存しません。")
            Write-Warn ("  {0}" -f $ConfigPath)
            Write-Warn ("  {0}" -f $_.Exception.Message)
            $script:ConfigReadOnly = $true
        }
    }

    $cfg.OutDir        = [string]$cfg.OutDir
    $cfg.CookieBrowser = ([string]$cfg.CookieBrowser).Trim()
    if (-not $cfg.CookieBrowser) { $cfg.CookieBrowser = $Defaults.CookieBrowser }
    $n = 0
    if (-not [int]::TryParse([string]$cfg.TitleBytes, [ref]$n) -or $n -lt 20) { $n = $Defaults.TitleBytes }
    $cfg.TitleBytes = $n
    $cfg.Mode = [string]$cfg.Mode
    if (-not $Modes.Contains($cfg.Mode)) { $cfg.Mode = $Defaults.Mode }
    # true / "true" のどちらで書かれていても受け付ける
    $cfg.Cookies  = ([string]$cfg.Cookies  -eq 'true')
    $cfg.Playlist = ([string]$cfg.Playlist -eq 'true')

    $script:Config = $cfg
    if (-not (Test-Path -LiteralPath $ConfigPath)) { Save-Config }
}

# 設定ファイルに保存（BOM なし UTF-8）
function Save-Config {
    if ($script:ConfigReadOnly) { return }
    try {
        $json = [pscustomobject]$Config | ConvertTo-Json
        [IO.File]::WriteAllText($ConfigPath, $json, (New-Object Text.UTF8Encoding($false)))
    } catch {
        Write-Warn ("設定を保存できませんでした: {0}" -f $_.Exception.Message)
        $script:ConfigReadOnly = $true
    }
}

# 保存先の実際のパス（空ならデスクトップ。環境変数を展開し、/ は \ に直す）
function Resolve-OutDir {
    $d = $Config.OutDir.Trim()
    if (-not $d) { return [Environment]::GetFolderPath('Desktop') }
    return ([Environment]::ExpandEnvironmentVariables($d) -replace '/', '\')
}

# 依存ツールの確認と、足りないものの winget インストール
function Initialize-Dependencies {
    $deps = @(
        @{ Cmd = 'yt-dlp.exe'; Id = 'yt-dlp.yt-dlp'; Desc = 'yt-dlp 本体';                      Required = $true  },
        @{ Cmd = 'ffmpeg.exe'; Id = 'Gyan.FFmpeg';   Desc = 'FFmpeg（映像と音声の結合・変換）';  Required = $false },
        @{ Cmd = 'deno.exe';   Id = 'DenoLand.Deno'; Desc = 'Deno（YouTube の JS チャレンジ用）'; Required = $false }
    )
    $missing = @($deps | Where-Object { -not (Test-Command $_.Cmd) })
    if ($missing.Count -eq 0) { return $true }

    Write-Warn '次のツールが見つかりません:'
    foreach ($d in $missing) { Write-Warn ("  - {0}" -f $d.Desc) }

    if (-not (Test-Command 'winget.exe')) {
        Write-Err 'winget がないため自動インストールできません。手動で入れてください。'
        return -not ($missing | Where-Object { $_.Required })
    }

    $ans = Read-Host 'winget でインストールしますか？ [Y/n]'
    if ($ans -match '^(n|no)$') {
        return -not ($missing | Where-Object { $_.Required })
    }
    foreach ($d in $missing) {
        Write-Info ("インストール中: {0}" -f $d.Id)
        [void](Invoke-Native 'winget.exe' @('install', '--id', $d.Id, '-e', '--accept-source-agreements', '--accept-package-agreements'))
    }
    Update-SessionPath
    if (-not (Test-Command 'yt-dlp.exe')) {
        Write-Err 'yt-dlp.exe がまだ見つかりません。このウィンドウを閉じて開き直してください。'
        return $false
    }
    return $true
}

# yt-dlp・Deno・FFmpeg をまとめて更新
# 実際に使われる exe の場所で更新方法を変える。
# （この .bat と同じフォルダの exe は PATH の先頭なので、winget で更新しても使われるのは古いまま）
function Update-Tools {
    $tools = @(
        @{ Cmd = 'yt-dlp.exe'; Id = 'yt-dlp.yt-dlp'; Name = 'yt-dlp' },
        @{ Cmd = 'deno.exe';   Id = 'DenoLand.Deno'; Name = 'Deno'   },
        @{ Cmd = 'ffmpeg.exe'; Id = 'Gyan.FFmpeg';   Name = 'FFmpeg' }
    )
    $hasWinget = Test-Command 'winget.exe'

    foreach ($t in $tools) {
        $src = Get-CommandSource $t.Cmd
        if (-not $src) {
            Write-Warn ("{0} が見つかりません（スキップ）" -f $t.Name)
            continue
        }
        if (Test-InSelfDir $src) {
            # 同じフォルダに置いた exe は自己更新するか、手動で差し替える
            switch ($t.Name) {
                'yt-dlp' { Write-Info 'yt-dlp を更新（同じフォルダの exe）'; [void](Invoke-Native $src @('-U')) }
                'Deno'   { Write-Info 'Deno を更新（同じフォルダの exe）';   [void](Invoke-Native $src @('upgrade')) }
                default  { Write-Warn ("{0} は同じフォルダの exe なので自動更新できません。新しい版を手動で差し替えてください。" -f $t.Name) }
            }
        } elseif ($hasWinget) {
            Write-Info ("更新確認: {0}" -f $t.Id)
            [void](Invoke-Native 'winget.exe' @('upgrade', '--id', $t.Id, '-e', '--accept-source-agreements', '--accept-package-agreements'))
        } elseif ($t.Name -eq 'yt-dlp') {
            [void](Invoke-Native $src @('-U'))
        } else {
            Write-Warn ("{0} は winget がないため自動更新できません。" -f $t.Name)
        }
    }
    Update-SessionPath
    $ver = Get-CommandSource 'yt-dlp.exe'
    if ($ver) { Write-Ok ('yt-dlp のバージョン: ' + (& $ver --version)) }
}

# 文字列から http(s) の URL を取り出す（空白・改行区切りで複数可、重複は除く）
# 「」や () で囲まれていたり、文末の 。 . , が付いていたりしても URL 部分だけを取る
function Get-UrlsFromText([string]$Text) {
    if (-not $Text) { return @() }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $urls = foreach ($m in [regex]::Matches($Text, 'https?://[^\s"''<>`「」『』【】（）＜＞、。，．！？]+')) {
        $u = $m.Value.TrimEnd('.', ',', ';', ':', '!', '?')
        # 末尾の ) は、URL 内に対応する ( がなければ外側の括弧とみなして外す
        while ($u.EndsWith(')') -and ($u.Split('(').Count -lt $u.Split(')').Count)) {
            $u = $u.Substring(0, $u.Length - 1).TrimEnd('.', ',', ';', ':', '!', '?')
        }
        if ($u -match '^https?://.+' -and $seen.Add($u)) { $u }
    }
    return @($urls)
}

# クリップボードから URL を取り出す
function Get-ClipboardUrls {
    try {
        $text = Get-Clipboard -Raw -ErrorAction Stop
    } catch {
        return @()
    }
    return Get-UrlsFromText $text
}

# 動画ファイルの直リンクか（ページ URL ではないか）
function Test-DirectMedia([string]$Url) {
    return ($Url -match '\.(m3u8|mpd|mp4|webm|mkv|m4a|mp3|ts)(\?|$)') -or ($Url -match 'X-Amz-Signature=')
}

# 署名付き URL（S3 形式）の有効期限を返す。該当しなければ $null
function Get-SignedUrlExpiry([string]$Url) {
    if ($Url -notmatch 'X-Amz-Date=(\d{8}T\d{6}Z)') { return $null }
    $date = $Matches[1]
    if ($Url -notmatch 'X-Amz-Expires=(\d+)') { return $null }
    $sec = [int]$Matches[1]
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    $issued = [datetime]::ParseExact($date, "yyyyMMdd'T'HHmmss'Z'", [Globalization.CultureInfo]::InvariantCulture, $styles)
    return $issued.AddSeconds($sec).ToLocalTime()
}

function Show-Status {
    $mode = $Modes[$Config.Mode].Name
    $cookie = if ($Config.Cookies) { "ON（$($Config.CookieBrowser)）" } else { 'OFF' }
    $pl = if ($Config.Playlist) { 'ON（全部）' } else { 'OFF（1本だけ）' }
    Write-Host ''
    Write-Host '──────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host (" 保存先: {0}" -f $OutDir)
    Write-Host (" モード: {0}   cookie: {1}   再生リスト: {2}" -f $mode, $cookie, $pl)
    Write-Host ' [m]モード  [c]cookie  [p]再生リスト  [o]保存先を開く  [u]更新  [q]終了' -ForegroundColor DarkGray
    Write-Host '──────────────────────────────────────────────' -ForegroundColor DarkGray
}

function Select-Mode {
    foreach ($k in $Modes.Keys) {
        $mark = if ($k -eq $Config.Mode) { '*' } else { ' ' }
        Write-Host (" {0} [{1}] {2}" -f $mark, $k, $Modes[$k].Name)
    }
    $ans = (Read-Host '番号を入力（Enter で変更しない）').Trim()
    if ($Modes.Contains($ans)) {
        $Config.Mode = $ans
        Save-Config
        Write-Ok ("モード: {0}" -f $Modes[$ans].Name)
    }
}

# ファイル名に使えない文字を _ に置き換える
function Get-SafeFileName([string]$Name) {
    $s = ($Name -replace '[\\/:*?"<>|\x00-\x1f]', '_').Trim().TrimEnd('.', ' ')
    if ($s.Length -gt 120) { $s = $s.Substring(0, 120).TrimEnd('.', ' ') }
    return $s
}

# 保存先に同じ名前（拡張子違いを含む）があれば "名前 (2)" のように番号を付ける
function Get-UniqueBaseName([string]$Dir, [string]$Base) {
    $names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if (Test-Path -LiteralPath $Dir) {
        foreach ($f in [IO.Directory]::EnumerateFiles($Dir)) {
            [void]$names.Add([IO.Path]::GetFileNameWithoutExtension($f))
        }
    }
    $cand = $Base
    $i = 2
    while ($names.Contains($cand)) {
        $cand = "$Base ($i)"
        $i++
    }
    return $cand
}

# 1 本ダウンロードする。成功なら $true
function Invoke-Download([string]$Url) {
    $tb = $Config.TitleBytes
    $outTmpl = "%(title).${tb}B [%(id).20B].%(ext)s"

    $direct = Test-DirectMedia $Url
    $expiry = Get-SignedUrlExpiry $Url
    $ref = ''
    if ($direct) {
        Write-Warn '動画ファイルの直リンクです。'
        if ($expiry) {
            $left = [int][math]::Floor(($expiry - (Get-Date)).TotalMinutes)
            if ($left -lt 0) {
                Write-Err ("このURLは {0:yyyy-MM-dd HH:mm} に期限切れです。元ページからURLを取り直してください。" -f $expiry)
                return $false
            }
            Write-Warn ("URLの有効期限: {0:yyyy-MM-dd HH:mm}（残り約 {1} 分）" -f $expiry, $left)
        }
        $ref = (Read-Host '元ページのURL（403 対策。不要なら Enter）').Trim().Trim('"')

        # 直リンクは URL の末尾（master.m3u8 なら master）がタイトルと ID になり、
        # 別の動画でも同じファイル名になって「ダウンロード済み」と判断され飛ばされる。
        # そのためファイル名をここで決め、既存ファイルと重ならないようにする。
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $name = Get-SafeFileName ((Read-Host ("ファイル名（拡張子なし。Enter で {0}）" -f $stamp)).Trim().Trim('"'))
        if (-not $name) { $name = $stamp }
        $name = Get-UniqueBaseName $OutDir $name
        # % は yt-dlp の出力テンプレートの記号なので %% にする
        $outTmpl = ($name -replace '%', '%%') + '.%(ext)s'
        Write-Info ("保存名: {0}" -f $name)
    }

    $ytArgs = @()
    $ytArgs += $Modes[$Config.Mode].Args
    $ytArgs += @(
        '--embed-metadata', '--embed-thumbnail', '--embed-chapters',
        '--progress', '--console-title', '--windows-filenames',
        '-P', $OutDir,
        '-o', $outTmpl
    )
    if ($Config.Playlist) { $ytArgs += '--yes-playlist' } else { $ytArgs += '--no-playlist' }
    if ($Config.Cookies)  { $ytArgs += @('--cookies-from-browser', $Config.CookieBrowser) }
    if ($ref)             { $ytArgs += @('--referer', $ref) }

    Write-Info ("ダウンロード開始: {0}" -f $Url)
    $ytArgs += @('--', $Url)
    $code = Invoke-Native 'yt-dlp.exe' $ytArgs

    if ($code -eq 0) {
        Write-Ok '完了しました。'
        return $true
    }

    Write-Err ("失敗しました（終了コード {0}）。" -f $code)
    if ($direct -and $expiry -and ((Get-Date) -gt $expiry)) {
        Write-Warn '・URLの期限が切れています。元ページからURLを取り直してください。'
    } elseif ($direct) {
        Write-Warn '・403 なら元ページのURLを入れて再試行、ログインが必要なページなら [c] で cookie を ON に。'
    } else {
        Write-Warn '・まず [u] で更新。年齢制限・会員限定なら [c] で cookie を ON に。'
        Write-Warn '・Unsupported URL なら非対応サイト。ブラウザの開発者ツールで .m3u8 の直リンクを探して貼ってください。'
    }
    return $false
}

# ---------------------------------------------------------------------
# メイン
# ---------------------------------------------------------------------
Import-Config
$OutDir = Resolve-OutDir

if (-not (Initialize-Dependencies)) {
    Read-Host 'Enter で終了'
    exit 1
}
if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}

Write-Ok 'URL をコピーしてから Enter を押すとダウンロードします（URL を直接貼り付けても可、複数可）。'
Write-Host (" 設定ファイル: {0}" -f $ConfigPath) -ForegroundColor DarkGray

:main while ($true) {
    Show-Status

    # クリップボードの URL（このセッションでダウンロード済みのものは除く）
    $clipUrls = @(Get-ClipboardUrls | Where-Object { -not $State.Done.Contains($_) })
    if ($clipUrls.Count -gt 0) {
        $preview = $clipUrls[0]
        if ($preview.Length -gt 90) { $preview = $preview.Substring(0, 90) + '…' }
        Write-Host (" クリップボード: {0}" -f $preview) -ForegroundColor Magenta
        if ($clipUrls.Count -gt 1) { Write-Host ("   ほか {0} 件" -f ($clipUrls.Count - 1)) -ForegroundColor Magenta }
        $prompt = 'URL（Enter でクリップボードのURLを使う）'
    } else {
        $prompt = 'URL'
    }

    $inputText = Read-Host $prompt
    if ($null -eq $inputText) { break main }
    $cmd = $inputText.Trim()

    switch -Regex ($cmd) {
        '^q$' { break main }
        '^m$' { Select-Mode; continue main }
        '^c$' { $Config.Cookies  = -not $Config.Cookies;  Save-Config; continue main }
        '^p$' { $Config.Playlist = -not $Config.Playlist; Save-Config; continue main }
        '^o$' { Start-Process explorer.exe $OutDir; continue main }
        '^u$' { Update-Tools; continue main }
    }

    if ($cmd -eq '') {
        $urls = $clipUrls
        if ($urls.Count -eq 0) { continue main }
    } else {
        # 直接入力した URL は処理済みでもダウンロードする（やり直したいとき用）
        $urls = @(Get-UrlsFromText $cmd)
        if ($urls.Count -eq 0) {
            Write-Warn 'URL が見つかりません（http:// か https:// で始まるものを入れてください）。'
            continue main
        }
    }

    $ok = 0
    foreach ($u in $urls) {
        # 成功したものだけ処理済みにする（失敗したものは [c] などで設定を変えて Enter で再試行できる）
        if (Invoke-Download $u) {
            $ok++
            [void]$State.Done.Add($u)
        }
    }
    if ($urls.Count -gt 1) {
        Write-Info ("{0} 件中 {1} 件成功" -f $urls.Count, $ok)
    }
    $Host.UI.RawUI.WindowTitle = 'yt-dlp ランチャー'
}
