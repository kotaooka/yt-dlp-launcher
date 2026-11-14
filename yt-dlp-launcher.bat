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

# ===== 設定（必要に応じて書き換える）=====
$Config = @{
    # 保存先（既定はデスクトップ。OneDrive にリダイレクトされていても正しく解決される）
    OutDir        = [Environment]::GetFolderPath('Desktop')
    # cookie を読むブラウザ（firefox 推奨。Windows 版 Chrome は暗号化の変更で読めないことが多い）
    CookieBrowser = 'firefox'
    # ファイル名のタイトル部分の上限（バイト）。Windows のファイル名長制限対策
    TitleBytes    = 80
    # 起動時の既定モード（下の $Modes のキー）
    DefaultMode   = '1'
}

# ===== ダウンロードモード =====
$Modes = [ordered]@{
    '1' = @{ Name = '最高画質 (mkv)';                Args = @('-f', 'bv*+ba/b', '--merge-output-format', 'mkv') }
    '2' = @{ Name = '互換性重視 (mp4 / H.264+AAC)';  Args = @('-S', 'vcodec:h264,res,acodec:aac', '--merge-output-format', 'mp4') }
    '3' = @{ Name = '音声のみ (mp3)';                Args = @('-x', '--audio-format', 'mp3', '--audio-quality', '0') }
    '4' = @{ Name = '音声のみ (元の形式・無変換)';   Args = @('-x', '--audio-format', 'best') }
}

# ===== 実行時の状態 =====
$State = @{
    Mode     = $Config.DefaultMode
    Cookies  = $false
    Playlist = $false
    LastUrl  = $null
}

$ErrorActionPreference = 'Continue'
$Host.UI.RawUI.WindowTitle = 'yt-dlp ランチャー'

# ---------------------------------------------------------------------
# 共通関数
# ---------------------------------------------------------------------

# PATH を再読み込み（winget でインストールした直後に反映させるため）
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function Test-Command([string]$Name) {
    return [bool](Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue)
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
function Update-Tools {
    if (Test-Command 'winget.exe') {
        foreach ($id in @('yt-dlp.yt-dlp', 'DenoLand.Deno', 'Gyan.FFmpeg')) {
            Write-Info ("更新確認: {0}" -f $id)
            [void](Invoke-Native 'winget.exe' @('upgrade', '--id', $id, '-e', '--accept-source-agreements', '--accept-package-agreements'))
        }
        Update-SessionPath
    } else {
        [void](Invoke-Native 'yt-dlp.exe' @('-U'))
    }
    Write-Ok ('yt-dlp のバージョン: ' + (yt-dlp.exe --version))
}

# クリップボードから http(s) の URL を取り出す（複数行なら全部）
function Get-ClipboardUrls {
    try {
        $text = Get-Clipboard -Raw -ErrorAction Stop
    } catch {
        return @()
    }
    if (-not $text) { return @() }
    return @([regex]::Matches($text, 'https?://\S+') | ForEach-Object { $_.Value })
}

# 入力文字列から URL を取り出す（空白・改行区切りで複数可、前後の " は除去）
function Get-UrlsFromText([string]$Text) {
    return @([regex]::Matches($Text, 'https?://[^\s"]+') | ForEach-Object { $_.Value })
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
    $mode = $Modes[$State.Mode].Name
    $cookie = if ($State.Cookies) { "ON（$($Config.CookieBrowser)）" } else { 'OFF' }
    $pl = if ($State.Playlist) { 'ON（全部）' } else { 'OFF（1本だけ）' }
    Write-Host ''
    Write-Host '──────────────────────────────────────────────' -ForegroundColor DarkGray
    Write-Host (" 保存先: {0}" -f $Config.OutDir)
    Write-Host (" モード: {0}   cookie: {1}   再生リスト: {2}" -f $mode, $cookie, $pl)
    Write-Host ' [m]モード  [c]cookie  [p]再生リスト  [o]保存先を開く  [u]更新  [q]終了' -ForegroundColor DarkGray
    Write-Host '──────────────────────────────────────────────' -ForegroundColor DarkGray
}

function Select-Mode {
    foreach ($k in $Modes.Keys) {
        $mark = if ($k -eq $State.Mode) { '*' } else { ' ' }
        Write-Host (" {0} [{1}] {2}" -f $mark, $k, $Modes[$k].Name)
    }
    $ans = (Read-Host '番号を入力（Enter で変更しない）').Trim()
    if ($Modes.Contains($ans)) {
        $State.Mode = $ans
        Write-Ok ("モード: {0}" -f $Modes[$ans].Name)
    }
}

# 1 本ダウンロードする。成功なら $true
function Invoke-Download([string]$Url) {
    $tb = $Config.TitleBytes
    $ytArgs = @()
    $ytArgs += $Modes[$State.Mode].Args
    $ytArgs += @(
        '--embed-metadata', '--embed-thumbnail', '--embed-chapters',
        '--progress', '--console-title', '--windows-filenames',
        '-P', $Config.OutDir,
        '-o', "%(title).${tb}B [%(id).20B].%(ext)s"
    )
    if ($State.Playlist) { $ytArgs += '--yes-playlist' } else { $ytArgs += '--no-playlist' }
    if ($State.Cookies)  { $ytArgs += @('--cookies-from-browser', $Config.CookieBrowser) }

    $direct = Test-DirectMedia $Url
    $expiry = Get-SignedUrlExpiry $Url
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
        if ($ref) { $ytArgs += @('--referer', $ref) }
    }

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
if (-not (Initialize-Dependencies)) {
    Read-Host 'Enter で終了'
    exit 1
}
if (-not (Test-Path -LiteralPath $Config.OutDir)) {
    New-Item -ItemType Directory -Path $Config.OutDir | Out-Null
}

Write-Ok 'URL をコピーしてから Enter を押すとダウンロードします（URL を直接貼り付けても可、複数可）。'

:main while ($true) {
    Show-Status

    # クリップボードの URL（直前にダウンロードしたものは除く）
    $clipUrls = @(Get-ClipboardUrls | Where-Object { $_ -ne $State.LastUrl })
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
        '^c$' { $State.Cookies = -not $State.Cookies; continue main }
        '^p$' { $State.Playlist = -not $State.Playlist; continue main }
        '^o$' { Start-Process explorer.exe $Config.OutDir; continue main }
        '^u$' { Update-Tools; continue main }
    }

    if ($cmd -eq '') {
        $urls = $clipUrls
        if ($urls.Count -eq 0) { continue main }
    } else {
        $urls = Get-UrlsFromText $cmd
        if ($urls.Count -eq 0) {
            Write-Warn 'URL が見つかりません（http:// か https:// で始まるものを入れてください）。'
            continue main
        }
    }

    $ok = 0
    foreach ($u in $urls) {
        if (Invoke-Download $u) { $ok++ }
        $State.LastUrl = $u
    }
    if ($urls.Count -gt 1) {
        Write-Info ("{0} 件中 {1} 件成功" -f $urls.Count, $ok)
    }
    $Host.UI.RawUI.WindowTitle = 'yt-dlp ランチャー'
}
