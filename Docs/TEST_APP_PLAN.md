# 本番と分けたテスト用アプリ（D8・T-065。2026-10-22）

利用者の条件（D8、2026-10-22）: 専用の端末2台と別の Apple Account 2つは用意できない。
いまの端末に、本番と分けたテスト用のアプリを一緒に入れられるか調べる。**名前を変えるだけで安全と判断しない。**
利用者とパートナーが日常で使っている家計簿で、削除・入れ直し・共有をやめることをしない。

**この文書は調査と計画まで。Apple Developer の変更・プロファイルの作成・ワークフローの追加は、まだ何もしていない。**

---

## 1. 結論

1. いまの `ios-dev-build.yml` は、**Bundle ID が本番と同じ**（`jp.aikawa.futarikakeibo`）。分けているのは CloudKit の環境（Development）だけ。
   日常の端末には入れられない（2026-09-28 の記録: TestFlight の版を Ad Hoc の版で置き換えられず、消すと端末の中の家計簿が消える）
2. **Bundle ID と CloudKit のコンテナを本番と別にしたテスト用アプリなら、同じ端末に並べて入れられる見込み。**
   端末の中の保存先・設定・通知はアプリごとに分かれ、CloudKit のデータはコンテナごとに分かれる（2章で1つずつ確かめた）
3. これで、入れ直し・共有をやめる・入り直し・共有の方式の検証（D1）を、日常の家計簿に触れずに、いまの2台と2つの Apple Account で行える。
   3人目の参加など一部だけは、3つ目の Apple Account か協力者が要る（`Docs/RELEASE_PLAN.md` 付録A）
4. 作るには、Apple Developer の変更（App ID・iCloud コンテナ・Ad Hoc プロファイル）と新しいワークフローが要る。3章の内容で承認をもらってから作る

## 2. 本番と同じになりうるものを1つずつ

| もの | いまの `ios-dev-build.yml` | テスト用アプリ（案） | 根拠・確かめ方 |
| --- | --- | --- | --- |
| 端末に入る場所 | 本番と同じ（置き換えになる。TestFlight の版は置き換えられない） | 別（並べて入る） | Bundle ID が別ならアプリは別。2026-09-28 の記録 |
| 端末の中の家計簿・レシート画像 | 本番と同じ | 別 | コード: `LocalSnapshotStore`・`ReceiptImageStore` はアプリの Application Support（アプリごとの入れ物）に置く |
| 設定（UserDefaults） | 同じ | 別 | コード: `UserDefaults.standard` だけ（App Group は使っていない） |
| iCloud の key-value | 同じ識別子 | 権限に入れない | entitlements に `ubiquity-kvstore-identifier` があるが、コードは使っていない（`NSUbiquitousKeyValueStore` の検索で0件） |
| CloudKit のコンテナ | 同じ（`iCloud.jp.aikawa.futarikakeibo`）。環境だけ Development | **別のコンテナ**（`iCloud.jp.aikawa.futarikakeibo.test`）の Development | コードは `CKContainer.default()`。どのコンテナが既定になるかは資料に書かれていない（"Every app has a default container that manages its own content." だけ）ので、テスト用の権限にはテスト用のコンテナ1つだけを入れ、名前も「`iCloud.` ＋ Bundle ID」にそろえる。書き出したアプリの権限をワークフローで読んで確かめる |
| CloudKit の環境 | Development | Development | 資料（CKContainer）: "At runtime, CloudKit uses your app's `com.apple.developer.icloud-container-environment` entitlement to discover whether you're using a Development or Production version"。いまのワークフローと同じく書き出しで指定し、権限を読んで確かめる |
| 合言葉（公開データベース） | Development の公開データベース | テスト用コンテナの公開データベース | 本番のアプリでテスト用の合言葉は引けず、逆も同じ |
| 共有のURLを開いたときに開くアプリ | 同じコンテナなので本番と取り合う | コンテナが別なので分かれる | `CKSharingSupported`。このアプリは合言葉からアプリの中で参加する |
| 通知 | 同じアプリなので混ざる | 別 | ローカル通知と CloudKit の購読はアプリごと。テスト用ではプッシュは確かめない（Ad Hoc と Development の組み合わせで届くか未確認） |
| Apple Account（iCloud） | 同じ | **同じ（変えない）** | iCloud からサインアウトする手順は入れない。テスト用コンテナのデータは利用者の iCloud の容量を少し使う |
| 設定 → iCloud の「ストレージを管理」 | — | テスト用アプリの名前で別に出る見込み（未確認） | 削除の確かめ（D14）では、消す前に名前を必ず見る |
| App Store Connect・TestFlight・本番のプロファイル・Secrets | 変えない | 変えない | Ad Hoc で書き出し、App Store Connect には送らない |
| 画面 | 同じ | 名前を「家計簿テスト」、画面の上に「テスト用（本番の家計簿とは別）」 | 取り違えを防ぐ。Bundle ID を見て出す（本番の Bundle ID では出ない） |

## 3. 承認が要る操作（まだ何もしていない）

| # | 操作 | どこで・だれが | 本番への影響 | 元に戻すとき |
| --- | --- | --- | --- | --- |
| 1 | iCloud コンテナ `iCloud.jp.aikawa.futarikakeibo.test` を作る | Apple Developer（Certificates, Identifiers & Profiles → Identifiers → iCloud Containers）・利用者 | 無い | 削除の方法を Apple の資料で確かめられなかった。消せないものとして考える（使わなければ中身は空のまま残るだけ） |
| 2 | App ID `jp.aikawa.futarikakeibo.test` を作り、iCloud（CloudKit）を有効にして 1 のコンテナを選ぶ | Apple Developer・利用者（App ID は API でも作れるが、コンテナを選ぶのはポータル） | 無い（本番の App ID `jp.aikawa.futarikakeibo` は触らない） | App ID は消せる |
| 3 | Ad Hoc プロファイル `FutariKakeibo Test Ad Hoc` を作る（2 の App ID、いまの配布用の証明書、登録済みの端末） | ワークフローから App Store Connect API で・Claude | 無い。本番の `FutariKakeibo App Store` と既存の `FutariKakeibo Ad Hoc` は触らない（いまのスクリプトは同じ名前のものだけ消して作り直す） | プロファイルは消せる |
| 4 | 2台の UDID の登録（未登録なら） | 3 と同じワークフロー・利用者が UDID を渡す | 無い | — |
| 5 | テスト用アプリを作るワークフロー `ios-test-app.yml` を足す。手で起動したときだけ動き、Ad Hoc で書き出し、権限（コンテナが1つだけでテスト用であること・環境が Development であること・Bundle ID）を読んで確かめ、IPA を成果物に置く | GitHub・Claude（**ワークフローの文面の承認のあと**） | `ios.yml`（配信）は変えない | ファイルを消す |
| 6 | テスト用の権限ファイルと、画面の「テスト用」の表示を足す | コード・Claude | 本番のビルドは本番の権限ファイルのまま。表示は本番の Bundle ID では出ない（テストで押さえる） | 差し戻す |
| 7 | IPA を iPhone に入れる | 2026-09-28 と同じ OTA（受け渡しサービスか、自分の置き場）・利用者 | 無い | テスト用アプリを消す（テスト用の家計簿だけが消える） |
| 8 | 既存の `ios-dev-build.yml` に「日常の端末に入れない」注意を足すか、テスト用アプリに置き換える | GitHub・Claude（文面の承認のあと） | — | — |

## 4. テスト用アプリで確かめられること・確かめられないこと

- **確かめられる:** `Docs/RELEASE_PLAN.md` 付録Aの「分けたテスト環境が要る」もの（入れ直しと取り戻し、共有をやめる、入り直しで未同期のデータが残るか、合言葉の1回利用の一部、共有の方式の検証 `Docs/SHARING_REVOCATION_DESIGN.md` 6章の V1・V2・V4〜V9、削除の確かめ（D14）の一部）
- **別のものが要る:** 3人目の参加（3つ目の Apple Account）、同じ Apple Account の2台目での取り戻し（同じ Account で入れる別の端末）、AIが動く端末での読み取り（D7）
- **テスト用アプリでは代わりにならない:** Production の環境でしか起きないこと（TestFlight・App Store の版、本番のスキーマと Security Roles、設定からの削除が Production のデータにどう効くか）。テスト用アプリは Development なので、そこで分かったことを本番に当てはめるときは、違いを書き添える

## 5. 本番と取り違えないための決まり

- テスト用アプリの名前は「家計簿テスト」、画面の上に「テスト用（本番の家計簿とは別）」
- テスト用アプリで発行した合言葉は、本番のアプリでは使えない（コンテナが別）。逆も同じ
- 「設定 → iCloud → ストレージを管理」で消すときは、名前が「家計簿テスト」であることを必ず確かめる
- 本番のアプリでは、付録Aの「いまの端末で安全にできる」ものだけを行う
