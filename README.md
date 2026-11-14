# yt-dlpランチャー（yt-dlp-launcher）

[yt-dlp](https://github.com/yt-dlp/yt-dlp) をダブルクリックで使うための Windows 用ランチャーです。ファイルは `.bat` ひとつだけです。

URL をコピーしてランチャーで Enter を押すだけで、最高画質でダウンロードできます。

## 機能

- **クリップボードの URL を自動で検出**: コピーしてから Enter を押すだけ。URL を直接貼り付けてもよく、空白や改行で区切れば複数件まとめて処理する
- **4 つのモードを切り替え**
  1. 最高画質（mkv）
  2. 互換性重視（mp4 / H.264+AAC）
  3. 音声のみ（mp3）
  4. 音声のみ（元の形式のまま・無変換）
- **cookie の ON/OFF**: 年齢制限や会員限定の動画向け。ブラウザの cookie を読み込む
- **再生リストの ON/OFF**: OFF なら、URL に `&list=` が付いていても 1 本だけ落とす
- **動画ファイルの直リンク（`.m3u8` / `.mp4` など）に対応**
  - 署名付き URL なら有効期限と残り時間を表示する
  - 403 対策として、元ページの URL（Referer）を入力できる
- **ファイル名を自動で切り詰める**: Windows のファイル名長の制限で `[Errno 22]` になるのを防ぐ
- **依存ツールの確認と導入**: yt-dlp / FFmpeg / Deno がなければ、起動時に winget でインストールできる
- **[u] でまとめて更新**: yt-dlp / Deno / FFmpeg を一度に更新する

## 導入

### 1. ランチャーを入手する

次のどちらかの方法で入手し、`yt-dlp-launcher.bat` を好きな場所（デスクトップなど）に置きます。

- **[Releases](../../releases/latest) から入手（推奨）**: **Assets** にある `yt-dlp-launcher.bat` をダウンロードする
- **ZIP で入手**: このページの **Code → Download ZIP** でダウンロードし、展開する

> **ファイル一覧の画面から `yt-dlp-launcher.bat` を開き、Raw や Download raw file で保存したものは動きません。** この方法だと改行コードが LF のまま保存されるためで、cmd は CRLF でないと正しく読めません。Releases か ZIP から入手してください。

### 2. yt-dlp・FFmpeg・Deno を入れる

ランチャーを動かすには、次の 3 つのツールが必要です。

| ツール | 用途 | 必須か |
|---|---|---|
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | ダウンロード本体 | 必須 |
| [FFmpeg](https://ffmpeg.org/) | 映像と音声の結合、mp3 への変換、サムネの埋め込み | 実質必須（ないと最高画質の映像と音声が別ファイルのまま残る） |
| [Deno](https://deno.com/) | YouTube の JavaScript チャレンジを解く | YouTube を使うなら必須（2025-11 以降の yt-dlp で必要） |

方法は次の 3 通りです。どれか 1 つで構いません。

**A. ランチャーに任せる（いちばん簡単）**

`yt-dlp-launcher.bat` をダブルクリックで起動します。足りないツールがあれば「winget でインストールしますか？」と聞かれるので、`Y` を押します。

**B. 自分で winget を使って入れる**

PowerShell かターミナルで次のコマンドを実行します。

```powershell
winget install yt-dlp.yt-dlp
winget install Gyan.FFmpeg
winget install DenoLand.Deno
```

入れた後は、ターミナルを開き直してから次のコマンドで確認します（それぞれバージョンが表示されれば OK）。

```powershell
yt-dlp --version
ffmpeg -version
deno --version
```

**C. winget を使わずに入れる**

それぞれの配布ページから exe をダウンロードし、**`yt-dlp-launcher.bat` と同じフォルダ**に置きます。ランチャーは起動時に自分のフォルダを PATH に加えるので、PATH の設定は要りません。

- yt-dlp: [Releases](https://github.com/yt-dlp/yt-dlp/releases/latest) の `yt-dlp.exe`
- FFmpeg: [gyan.dev](https://www.gyan.dev/ffmpeg/builds/) の essentials ビルドを展開し、`bin` 内の `ffmpeg.exe` と `ffprobe.exe`
- Deno: [Releases](https://github.com/denoland/deno/releases/latest) の `deno-x86_64-pc-windows-msvc.zip` を展開した `deno.exe`

この方法で入れた場合、[u] キーでは更新できません。それぞれ新しい exe に置き換えてください（yt-dlp だけは `yt-dlp.exe -U` で自動更新できます）。

### 3. 初回起動時の警告

インターネットから入手した `.bat` を初めて開くと、「Windows によって PC が保護されました」と表示されることがあります。その場合は **詳細情報 → 実行** で起動します。

毎回表示される場合は、ファイルを右クリック → **プロパティ** →「許可する」にチェックを入れて OK を押してください。

## 使い方

1. `yt-dlp-launcher.bat` をダブルクリックで起動する
2. 落としたい動画の URL をコピーし、ランチャーで Enter を押す

| キー | 動作 |
|---|---|
| Enter | クリップボードの URL をダウンロード |
| URL を貼り付けて Enter | その URL をダウンロード（複数可） |
| `m` | モードを切り替え |
| `c` | cookie の ON/OFF |
| `p` | 再生リストの ON/OFF |
| `o` | 保存先フォルダを開く |
| `u` | yt-dlp / Deno / FFmpeg を更新 |
| `q` | 終了 |

## 設定

ファイル先頭近くの `$Config` を書き換えます。

| 項目 | 既定値 | 内容 |
|---|---|---|
| `OutDir` | デスクトップ | 保存先 |
| `CookieBrowser` | `firefox` | cookie を読むブラウザ。Windows 版 Chrome は暗号化方式の変更により読めないことが多い |
| `TitleBytes` | `80` | ファイル名のタイトル部分の上限（バイト） |
| `DefaultMode` | `1` | 起動時のモード |

## 動作環境

- Windows 11（Windows 10 でも動く想定）
- Windows PowerShell 5.1（Windows に標準で入っているもの。PowerShell 7 は不要）
- yt-dlp / FFmpeg / Deno（[導入](#導入)を参照）

## うまくいかないとき

| 症状 | 対処 |
|---|---|
| `Sign in to confirm you're not a bot` / `HTTP Error 403` | まず [u] で更新する。直らなければ [c] で cookie を ON にする |
| `Unsupported URL` | そのサイトには yt-dlp が対応していない。[対応していないサイトから落とす](#対応していないサイトから落とす)の手順で、動画ファイルの URL を探して貼る |
| 映像と音声が別ファイルのまま残る | FFmpeg が入っていない |
| YouTube だけ失敗する | Deno が入っていない、または yt-dlp が古い |
| cookie を ON にしても失敗する | Chrome の cookie は読めないことが多い。Firefox でログインし、`CookieBrowser` を `firefox` にする |

それでも原因が分からないときは、PowerShell で `yt-dlp -v "URL"` を実行すると詳しいログが見られます。

## 対応していないサイトから落とす

`Unsupported URL` と出るサイトでも、ページの中で再生されている**動画ファイルそのものの URL** を貼れば、たいていダウンロードできます。

### 手順（Chrome / Edge / Firefox 共通）

1. 動画のあるページを開き、**F12** を押して開発者ツールを開く
2. **ネットワーク（Network）** タブを選ぶ
3. フィルタ欄に `m3u8` と入力し、ページを再読み込みして動画を再生する
4. 出てきた行を右クリック → **コピー** → **URL をコピー**
5. ランチャーで Enter を押す（クリップボードの URL がそのまま使われる）
6. 「元ページの URL」を聞かれたら、動画のあったページの URL を貼る（403 対策。不要なら Enter）

`m3u8` で何も出ないときは、フィルタを `mpd` → `mp4` の順に変えて探します。

### どの URL を選ぶか

| 見つかったもの | 中身 | 扱い |
|---|---|---|
| `master.m3u8` / `playlist.m3u8` | HLS の目録（複数の画質をまとめたもの） | これが最適。`master` があれば最高画質を選べる |
| `index_720p.m3u8` など | 特定の画質だけの目録 | 落とせるが、画質は固定 |
| `.mpd` | DASH の目録 | 落とせる |
| `.mp4` / `.webm` | 動画ファイルそのもの | そのまま落とせる |
| `.ts` / `.m4s` が大量に並ぶ | 細切れにされた断片 | これ自体は使わない。同時に読み込まれている `.m3u8` か `.mpd` を探す |

### 注意

- **URL には有効期限があることが多い**: `X-Amz-Expires` などが付いた署名付き URL は、数分〜数時間で使えなくなります。ランチャーは期限を読み取れる URL なら残り時間を表示します。期限が切れて `403` になったら、ページを開き直して URL を取り直してください
- **ログインが必要なページ**: [c] で cookie を ON にしてから貼ってください
- **DRM がかかっている配信は落とせません**: `DRM protected` と出る場合や、ネットワークタブに `license` や `widevine` を含む通信がある場合は、DRM で保護されています

## 仕組み

`.bat` の先頭は cmd と PowerShell の両方が読める書き方（polyglot）になっています。

- cmd は先頭の数行だけを実行し、自分自身を PowerShell に渡して終了する
- PowerShell は先頭の `<# : ... #>` をコメントとして読み飛ばし、残りを実行する

cmd 部分を壊さないように、**BOM なし UTF-8** で保存してください。

## 注意

- DRM で保護された配信はダウンロードできません
- 著作権や各サイトの利用規約の範囲内で使ってください

## ライセンス

MIT License
