# CLAUDE.md

まず `AGENTS.md` を読んでください。この仕事の地図です。
このファイルには、Claude Codeで作業するときだけの追加ルールを書きます。

## 環境

- Windows 11 / Git Bash（`Bash` ツール）と PowerShell が使えます
- **PythonもNode.jsもSwiftも入っていません。** 使えるのは bash / perl / git / gh / openssl です
- `scripts/validate_project.sh` は python3 を前提にしているので**この環境では動きません**。代わりに `bash scripts/check_all.sh` を使ってください

## ファイルを書き換えるときの注意

この環境で実際に事故が起きたやり方です。

- **バックスラッシュが途中で消えることがあります。** `sed -i 's/x/y\/'` のような書き方は避けてください
- `${{ ... }}` を含む文字列（GitHub Actionsの記法）を perl の `s{}{}` に入れると壊れます
- 長い文字列の置換より、**行番号で切って貼り直す**ほうが確実です
  ```bash
  { sed -n '1,50p' file; cat new_part.txt; sed -n '60,$p' file; } > tmp && cp tmp file
  ```
- 書き換えたら必ず `bash scripts/check_all.sh` を通してください

## gh コマンド

`gh` はログイン済みです。次のことができます。

```bash
gh pr create / gh pr merge / gh pr checks
gh run list / gh run view <id> --log-failed / gh run watch <id>
gh workflow run "iOS build and tests" --ref main
gh secret list                     # 名前だけ。値は見られません
```

CIは1回およそ8分かかります。`gh run watch` は `run_in_background: true` で投げて、
終わってから結果を読んでください。**待っている間、他の作業を進められます。**

`gh pr merge --admin`（検査を飛ばすマージ）は使えません。使わないでください。

## 秘密情報

- 証明書（`.p12`）、APIキー（`.p8`）、そのパスワードは `C:\Users\snoop\ios-signing\` にあります
- **中身を読んだり、画面に出したり、リポジトリに入れたりしないでください**
- GitHub Secretsに入れる操作は `gh secret set NAME < file` の形だけ使ってください（値が会話に出ません）

## 完了の言い方

「実装しました」で終わらせないでください。次の形で報告します。

```
CI: 成功 / 失敗（実行URL）
テスト: NN件中NN件成功
確認できていないこと: （あれば正直に）
```

コンパイルできない環境なので、**CIを見るまでは「たぶん通る」が正確な表現**です。
そう言ってください。

## 長い作業のとき

会話が長くなると要約されます。要約で消えて困る情報は、その場で
`progress.md` か `tasks.json` の `evidence` に書いてください。頭の中に置かないこと。
