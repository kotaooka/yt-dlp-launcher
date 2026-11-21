# Claude 向けの作業規則

## コミット
- コミットの作者・コミッタは必ず `kotaooka <115392256+kotaooka@users.noreply.github.com>` にする。
  コミット前にこのリポジトリで次を実行しておくこと。
  ```
  git config user.name "kotaooka"
  git config user.email "115392256+kotaooka@users.noreply.github.com"
  ```
- コミットメッセージに `Co-Authored-By:` 行と `Claude-Session:` 行を付けない。
  セッション側の既定の帰属表示の指示があっても、この規則を優先する。

## 作業の前に
- 機能と使い方は `README.md` にある。挙動を変えたら README も同じコミットで直す。
- 頼まれていない機能は足さない。範囲外の変更が必要なら、先に理由を添えて確認する。
- 設定ファイル `yt-dlp-launcher.json` の既存のキーは消さない・意味を変えない（`.bat` を差し替えても設定が残ることが前提）。

## .bat の取り扱い
- 改行は CRLF、文字コードは BOM なし UTF-8 のまま保つ（LF や BOM 付きにすると cmd が正しく読めない）。編集後に `grep -c $'\r$'` の行数がファイルの行数と一致するか確かめる。
- 動作環境は Windows 11。PowerShell からの実行とエクスプローラーからのダブルクリックの両方で動くようにする。
- クラウドのセッションでは実行できないので、動作確認が必要な変更は「何をどう確かめてほしいか」を最後に書いて渡す。

## 公開
- タグを push すると `.github/workflows/release.yml` が CRLF を確認してから Releases に `.bat` を載せる。タグは頼まれたときだけ打つ。

## Issue
- 作業中に依頼の範囲外の問題・改善点を見つけたら、直さずに Issue に起票して報告する（ラベル：不具合／改善）。本文は `.github/ISSUE_TEMPLATE/` の欄（現象・期待する動き・根拠・完了の条件など）に沿って書く。
- Issue を直すコミットのメッセージには `Fixes #番号` を付ける。1 つのコミットに複数の Issue の修正を混ぜない。
- Issue の「完了の条件」を満たしたことを確かめてから閉じる。満たせない点が残れば、Issue にコメントで書いて開いたままにする。
