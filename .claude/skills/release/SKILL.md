---
name: release
description: ふたり家計簿を TestFlight へ配信する。対象コミットの確認、テスト結果の確認、マージ、配信の起動、結果の確認、TestFlight側の確認、報告まで。実機で試したい・配信したいと言われたときに使う。
---

# TestFlight へ配信する

**TestFlightの内部テスト配信は Claude の担当です**（`CLAUDE.md`「分担と完了条件」、2026-10-14 利用者が決定）。
マージと配信の起動を利用者に頼まないでください。
App Store の公開・外部テスター・課金や契約の変更は**含みません**。そちらは毎回利用者に確認します。

以前このファイルに「配信の起動はAIにはできない、人間に渡す」と書いてありました。
2026-09-03 に**Windowsの `gh workflow run` が一度止められた**ことを、性質として一般化したものです。
クラウドでは GitHub MCP から起動できています（2026-10-14 までに5回）。
**止められる前から「できない」と言わないでください。** 先に `progress.md` と実行履歴を見ます。

## 1. 配信するコミットを決める

- 送るのは **`main` だけ**。ワークフローが `main` 以外では `testflight` ジョブを動かさない（2026-10-14 から）
- PR の head と、マージできるかを見る
  ```bash
  gh api repos/{owner}/{repo}/pulls/<番号> --jq '.head.sha, .mergeable_state'
  ```

## 2. テストの成功を確かめる

- その head の `test` ジョブが `success` であること
  ```bash
  gh api repos/{owner}/{repo}/commits/<SHA>/check-runs --jq '.check_runs[] | "\(.name) \(.conclusion)"'
  ```
- 件数は `mcp__github__get_job_logs`（`job_id`、`return_content: true`、`tail_lines: 30`）で
  `Executed NNN tests, with 0 failures` を読む
- **赤ならマージしない。** 直して push し直す

## 3. マージする

`mcp__github__merge_pull_request`

| 引数 | 値 |
| --- | --- |
| `merge_method` | `merge` |
| `expectedHeadSha` | **手順2でCIが見たSHA**。あとから push されたものを混ぜないため |

`gh pr merge --admin`（検査を飛ばす）は使わない。

## 4. 配信を起動する

`mcp__github__actions_run_trigger`

| 引数 | 値 |
| --- | --- |
| `method` | `run_workflow` |
| `workflow_id` | `ios.yml` |
| `ref` | `main` |

返事が `204 No Content` / `Workflow run has been queued` なら起動できている。
このワークフローに `inputs` は無い（`-f upload=true` は存在しない入力。2026-09-03 に誤って書いていた）。

Bash の `gh api .../dispatches` からは起動しない。auto モードの判定器に止められた（2026-10-14）。
**止められたら形を変えて通そうとせず、止めた層とエラー文を利用者に報告する。**

## 5. 実行結果を確かめる

状態は MCP で1回ずつ読む。

- `mcp__github__actions_list`（`list_workflow_runs`、`resource_id: "ios.yml"`、`event: workflow_dispatch`）で実行IDを得る
- `mcp__github__actions_list`（`list_workflow_jobs`、実行ID）でジョブとステップの進み具合
- ログは**ジョブが終わってから**でないと取れない（途中は404）

Bash のループで見張らない。読むだけでも `[Production Deploy]` として止められた（2026-10-14）。
待つあいだは他の作業を進め、合間に1回ずつ見る。

所要は**送信まで10〜20分**（テスト7〜14分 → アーカイブと送信3〜6分）。
そのあとの確認（手順6）に最長30分。テストのあいだ画面に何も出ないので、
利用者に伝えるときはこの内訳も渡す（7分を待ちきれずに「配信されていない」と見えたことがある）。

合格の印は `testflight` ジョブの末尾（`mcp__github__get_job_logs`、`tail_lines: 120`）。

| 見るもの | 意味 |
| --- | --- |
| `** EXPORT SUCCEEDED **` | 署名つきで書き出せた |
| `UPLOAD SUCCEEDED with no errors` と `Delivery UUID` | **Appleが受け取った** |
| `archive app:` の次の2行 | 版とビルド番号。**`1.0` / `1` なら Info.plist が上書きされている**（2026-09-01 の事故） |

## 6. TestFlight 側の状態を確かめる

送信のあと、`testflight-status` ジョブ（ubuntu）が App Store Connect に問い合わせて、
**処理が終わって内部テスターに配られたか**を最長30分待って確かめる（`scripts/testflight_status.rb`）。
鍵はこのジョブの中でだけ使う。**Claude は鍵を見ず、結果だけを読む。**

結果はジョブのログの最後の1行（`get_job_logs`）で読む。

```
TESTFLIGHT STATUS: ready version=0.2.0 build=2026.1014.1016 processingState=VALID internalBuildState=IN_BETA_TESTING
```

| 判定 | 意味 | ジョブ | すること |
| --- | --- | --- | --- |
| `ready` | 内部テスターに配られた | 緑 | 利用者に「入れられます」と報告 |
| `failed` | Apple側の処理に失敗 | 赤 | ログの理由を読み、直して出し直す |
| `needs_action` | 輸出コンプライアンスの回答待ち | 赤 | 利用者に App Store Connect での回答を頼む（Claudeにはできない） |
| `waiting` | 30分で確定しなかった | 緑 | 注記に最後の状態がある。そのまま報告する |
| 注記「鍵の権限で読めなかった」 | キーの役割が足りない | 緑 | 送信は成功している。利用者にキーの役割を確かめてもらう |

**2026-10-14 に入れた仕組みで、本物の鍵ではまだ一度も動いていない。** 最初の配信では必ず結果を読み、
うまく動かなければ `progress.md` に書いて直す。自己点検（`ruby scripts/testflight_status.rb --self-test`）は
PRのたびに `scripts` ジョブで走る。

## 7. 報告する

```
CI: 成功（実行URL）
テスト: NNN件中NNN件成功
配信: 版 X.Y.Z / ビルド YYYY.MMDD.HHMM、UPLOAD SUCCEEDED、TestFlight: ready（実行URL）
確認できていないこと: 実機での動作など
```

そのうえで、**どの画面の、何を見て、どうなっていれば合格か**を書く。「確認してください」だけで渡さない。
入っているビルドは、設定画面の一番下の行（例 `Version 0.2.0 (2026.1014.1016)`）で分かる。

最後に `progress.md` の「いまの状態」を書き換えて記録を3行足し、
`tasks.json` の該当タスクの `evidence` に実行URL・ビルド番号・テスト件数を書く。

## 版とビルド番号

- **ビルド番号は何もしなくてよい。** ワークフローが時刻から作る（年.月日.時分。例 `2026.1018.616`）ので、必ず前より大きくなる。各要素の先頭の0は落としてある（Apple側の表示と、設定画面の表示をそろえるため。T-032）
- **版（`MARKETING_VERSION`）は節目で手で上げる。毎回でなくてよい。** 同じ版の中でも、ビルド番号が大きい方が新しいものとして並ぶ
  - Initial commit から 2026-10-13 まで `0.1.0` のままで、2026-10-14 に `0.2.0` にした
- 上げるときは `project.yml` と `project.pbxproj`（2か所）を揃える。CIは `xcodegen generate` で作り直すので、**効くのは `project.yml`**

## 秘密（名前だけ。値は見ない）

ワークフローが使うのは6件です（`.github/workflows/ios.yml` が正）。

`APPLE_DISTRIBUTION_CERTIFICATE_BASE64` `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD` `APPLE_PROVISIONING_PROFILE_BASE64`
`APP_STORE_CONNECT_API_KEY_ID` `APP_STORE_CONNECT_API_ISSUER_ID` `APP_STORE_CONNECT_API_PRIVATE_KEY_BASE64`

クラウドの `gh api` では一覧も取れません（プロキシが `actions/secrets` を拒否する）。
**直前の配信が `UPLOAD SUCCEEDED` なら揃っています。**

## 失敗したときの読み方

| ログに出る文字 | 意味 | 対処 |
| --- | --- | --- |
| `error:` を含む行 | Swiftのコンパイルエラー | その行を直して push し直す |
| `Executed .. with 1 failure` | テストが落ちた | 落ちたテスト名を探す |
| `exit code 65` だけで本文が見えない | ビルドかテストの失敗 | **自分の差分を読み直すのが早い**（2026-10-14 はこれで見つけた） |
| `bundle version must be higher` | ビルド番号の重複 | 番号を上げ直す |
| `No profiles for ... were found` | 証明書か Provisioning Profile の期限切れ | 利用者に依頼（AIには作れない） |
| `passphrase you entered ... not correct` | `.p12` のパスワードか作り方 | `openssl pkcs12 -export -legacy` で作り直す。改行は `tr -d '\r\n'` |
| ジョブが `queued` のまま10分以上 | macOSランナーの空き待ち | 待つ。**枠が尽きたと決めつけない**（一度誤った） |

- ログの本文: `mcp__github__get_job_logs`（`failed_only: true` と `run_id`、または `job_id`）
- Bash の `gh api .../logs` は使えない。GitHubはログを別ホストから配っていて、`gh api` はそこへ行かない
- 注記: `gh api repos/{owner}/{repo}/check-runs/<id>/annotations`

## Windows（利用者のPC）で動いているとき

`gh workflow run ios.yml --ref main` は 2026-09-03 に Claude Code の権限で止められた記録があります。
同じように止められたら、止めた層とエラー文を利用者に報告してください。
GitHub の画面（スマホ可）からも同じワークフローを起動できます:
Actions → **iOS build and tests** → **Run workflow** → Branch が `main` → **Run workflow**
