---
name: release
description: ふたり家計簿を TestFlight へ配信する。ビルド番号の決め方、CIの起動、結果の確認、失敗したときの読み方まで。実機で試したい・配信したいと言われたときに使う。
---

# TestFlight へ配信する

**この作業は「本番への反映」です。実行前に人間の承認を取ってください（`Docs/safety.md`）。**

## 前提の確認

配信できる状態か、先に確かめます。

```bash
gh secret list
```

6件（`IOS_DIST_CERT_P12` `IOS_DIST_CERT_PASSWORD` `IOS_PROVISIONING_PROFILE` `ASC_KEY_ID` `ASC_ISSUER_ID` `ASC_PRIVATE_KEY`）が揃っていること。
足りなければ配信はできません。人間に依頼してください。

## ビルド番号

ここは何もしなくて構いません。**ワークフローが実行時刻から自動で作ります**（`date -u '+%Y.%m%d.%H%M'`）。
TestFlightは同じビルド番号を二度受け付けませんが、時刻から作るので必ず前より大きくなります。
バージョン（`MARKETING_VERSION` = `0.1.0`）は変わりません。

## 実行 — これはAIにはできません

```bash
gh workflow run ios.yml --ref main
```

**このコマンドはAIの実行権限で止められます。**「外部への配信を起こす操作」と判定されるためで、
`Docs/safety.md` のルールとは別の、ツール側の安全機構です。**人間に渡してください。**

`-f upload=true` は**存在しない入力**です（2026-09-03に誤って書いていました）。
このワークフローに `inputs` はなく、`workflow_dispatch` で起動しさえすれば
`testflight` ジョブが動きます（`if: github.event_name == 'workflow_dispatch'`）。

### PCが無いとき

GitHubのWeb画面から、スマホのブラウザでも実行できます。

1. `https://github.com/<owner>/<repo>/actions` を開く
2. 左の一覧から **iOS build and tests** を選ぶ
3. 右上の **Run workflow** → Branch が `main` であることを確認 → 緑の **Run workflow**

およそ15分かかります（テスト8分 + アーカイブと送信7分）。

起動したかどうかは、AIの権限でも確認できます。

```bash
gh run list --workflow=ios.yml --event workflow_dispatch --limit 1
```

## 結果の確認

**成功したかどうかは、必ずログで確かめます。「上げました」では終わりません。**

```bash
gh run view <実行ID> --json jobs -q '.jobs[]|"\(.name)\t\(.conclusion)"'
gh run view <実行ID> --log | grep -E "UPLOAD SUCCEEDED|Executed [0-9]+ test"
```

さらに、**アプリに実際に入った値**を確かめます。ここが `1.0 / 1` なら Info.plist が
上書きされている合図です（過去に起きた事故 — `progress.md` 2026-09-01 を参照）。

```bash
gh run view <実行ID> --log | grep -A4 "archive Info.plist"
```

## 失敗したときの読み方

| ログに出る文字 | 意味 | 対処 |
| --- | --- | --- |
| `error:` を含む行 | Swiftのコンパイルエラー | その行を直して push し直す |
| `Executed .. with 1 failure` | テストが落ちた | 落ちたテスト名を探す |
| `bundle version must be higher` | ビルド番号の重複 | 番号を上げ直す |
| `No profiles for ... were found` | 証明書か Provisioning Profile の期限切れ | 人間に依頼（AIには作れない） |
| `passphrase you entered ... not correct` | `.p12` のパスワードか作り方 | `openssl pkcs12 -export -legacy` で作り直す。改行は `tr -d '\r\n'` |
| ジョブが `queued` のまま10分以上 | macOSランナーの空き待ち | 待つ。**枠が尽きたと決めつけない**（一度誤った） |

```bash
gh run view <実行ID> --log-failed | grep -E "error:" | sort -u | head -20
```

## 配信のあと

1. App Store Connect → TestFlight でビルドが「処理中」から変わるのを待つ（10〜30分）
2. 輸出コンプライアンスの質問に答える（`ITSAppUsesNonExemptEncryption` を入れてあるので、通常は出ません）
3. `progress.md` に3行書く（バージョン、何を変えたか、確かめてほしいこと）
4. `tasks.json` の該当タスクの `evidence` に実行URLとビルド番号を書く

**人間に「確認してください」とだけ言わないでください。**
「どの画面の、何を見て、どうなっていれば合格か」を書いて渡します。
