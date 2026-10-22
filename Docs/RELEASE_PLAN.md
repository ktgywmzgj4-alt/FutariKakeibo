# App Store 公開までの計画（T-052。2026-10-22、同日 D1〜D14 の回答を反映）

利用者の依頼（2026-10-22）「最新のコードと開発状況を確かめ、安全な App Store 公開まで進めるための計画」への答えです。
台帳は `tasks.json` の T-052〜T-058 と、回答を受けた T-059〜T-072。

**この計画を作るあいだに、TestFlight の配信・App Store への提出・CloudKit Production の変更・共有の権限の変更はしていません。**

---

## 0. 読み方

調べたもの: main のコード、開いている PR（#28・#29）、CI と配信の実行のログ、Apple の公式の説明（原文を引用）。
文書には古い所がある（2-3）ので、文書だけを根拠に「済み」「未」を決めていない。

| ことば | 意味 |
| --- | --- |
| 実装済み | main のコードにある |
| CI確認済み | CI の自動テストで押さえていて、全件成功している |
| 実機確認済み | 利用者が iPhone で確かめた記録がある（`progress.md`・`tasks.json`） |
| 未確認 | 実機で確かめた記録が無い |

利用者の方針（2026-10-22）:

- 最優先は、安全に App Store で一般公開すること。初回は完全無料で、レシート読み取りを魅力として伝える
- 初期ユーザーを優遇する方針は続ける。対象・期間・回数は未定で、「永久無料」などの約束はしない
- AI家計評価は公開後に作る。いまあるレシート読み取りの AI補助をすぐ撤去する指示ではない
- 判断が要る点と、調べれば解決できる点を分ける。判断を求めるときは、推奨案・利用者への影響・必要な作業を書く

この回で足した文書:

| 文書 | 中身 |
| --- | --- |
| `Docs/SHARING_REVOCATION_DESIGN.md` | D1: 共有をやめたら入れない・古いURLでは入れない形の比べと推奨、検証の準備 |
| `Docs/TEST_APP_PLAN.md` | D8: 本番と分けたテスト用アプリ（同じ端末に並べる）と、承認が要る操作 |
| `Docs/PRIVACY_POLICY_REQUIREMENTS.md`（書き直し） | D2・D14: 保存する項目とだれが読めるか、申告の理由、削除で書けること・書けないこと |
| `Docs/drafts/` | D3: ポリシーとサポートページの原稿（個人の情報は空欄）、掲載先の推奨 |
| `Docs/SCREENSHOT_PLAN.md` | D9: 撮る画面と見出しの案、作り方の案 |
| `Docs/REQUIREMENTS_SAFETY_PROPOSAL.md` | D12: requirements.md・safety.md の改訂案（差分） |

---

## 1. 結論（先に）

1. **公開を止めているいちばん大きな問題は、共有の形。** いまは「共有のURLを知っている人なら参加できる」形で、共有をやめて始め直してもURLは同じ（Apple の資料で確かめた）。
   利用者の条件（D1）を満たすには「名指しの共有」に変える必要がある。**公開前に変えることを推奨**（公開後に変えると全利用者のパートナーが入り直す）。方法は3つあり、どれも実機で未確認なので、本番と分けたテスト用アプリで確かめてから選ぶ（3章）
2. **「開発者は家計データを読めない」は、いまは半分しか言えない。** データベースを直接は見られないが、公開データベースの合言葉のレコードにある共有のURLを使えば、開発者も参加できてしまう。名指しの共有にすれば両方言える（5-2）
3. **削除の代わりの手順が足りない。** 参加した人が抜けられない、作った人がふつうに共有をやめられない、消した記録の中身が iCloud に残る、公開データベースの記録が残る、設定からの削除は未確認。公開前の対策を提案する（5-4 の M1〜M5）
4. **実機の確かめは、テスト用アプリを作れば、いまの2台と2つの Apple Account でほとんどできる。** 3人目の参加など一部は、3つ目の Apple Account か協力者が要る（付録A）。テスト用アプリには Apple Developer の変更の承認が要る（`Docs/TEST_APP_PLAN.md` 3章）
5. この回の実装: Privacy Manifest に理由つきAPIを申告し、D10 の必須の条件（消した記録が戻らない・別々に足した記録が消えない）を2台を交互に同期させるテストで押さえた（PR #52、CI の結果は 2-1）
6. **気づいたこと: このリポジトリは公開（public）。** テスト用に入れた実際のレシートの写し（店・日時・金額・地域）も誰でも読める（2-3）

---

## 2. 現在地（2026-10-22）

### 2-1. CI と配信

| 項目 | 結果 | 根拠 |
| --- | --- | --- |
| PR #50 の CI | 352件中352件成功。[OCR評価] 変わらず（店名 14/15、合計 15/15、日付 15/15、種類 14/15、明細 71/71） | run 39718710537 |
| main の配信 | **2.0.0 / 2026.1022.404**。UPLOAD SUCCEEDED（Delivery UUID 7d2da067-8424-4955-90fa-990fd0b0d8e3）。TESTFLIGHT STATUS ready（VALID / IN_BETA_TESTING、13:10 JST） | run 39719822434 |
| 署名済みアプリの権限 | `aps-environment = production` が入った（アーカイブの `ProcessProductPackaging` の出力） | 同 testflight ジョブ |
| 配信用プロファイル | `FutariKakeibo App Store`（32041c47-2e08-4129-aa36-de92d0520ce0、期限 2027-09-01）。`aps-environment: production` | 同 signing-check ジョブ |
| PR #52（この回） | Privacy Manifest の理由つきAPI、D10 のテスト。コードの push の CI で **363件中363件成功**（352件＋足した11件）。[OCR評価] 変わらず | run 39769095647 |
| 開いている PR | #28（2人の目印の色）、#29（Release で診断を取る、ドラフト）。**どちらも初回公開に入れない**（D11。閉じる・ブランチを消すことはしない） | 9章 |

### 2-2. 機能ごとの状態

| 領域 | 実装 | CI | 実機 | メモ |
| --- | --- | --- | --- | --- |
| 支出・収入・定期支出・予算・月次レポート・CSV | 済 | 済 | 済（要件の F1〜F10） | 精算の計算のテストは3件と少ない（`LedgerCalculatorTests`） |
| 別の Apple ID の2台での共有 | 済 | 済 | **済**（2026-10-04、T-003） | いまのビルドでの再確認は未 |
| 合言葉の1回利用・参加者の一覧・2人より多い警告（T-040） | 済 | 済（`SharingSafetyTests`） | 未 | 付録A |
| 取り戻し（入れ直し、作った側・参加した側。T-023・T-041） | 済 | 済（`SyncMergeTests` ほか） | 未 | 付録A の B3 |
| 同期（オフライン・同時編集・削除印・入り直し） | 済 | 済。**2026-10-22 に2台を交互に同期させるテストを足した**（D10） | 未 | 3-7 |
| 相手の支出の通知（開いているあいだ。T-044〜T-046） | 済 | 済 | 未 | `Docs/NOTIFICATIONS.md` 5章 1〜8 |
| 閉じているあいだの通知（T-047） | 済 | 済 | 未 | 署名済みアプリに権限が入ったのは配信のログで確かめた |
| レシート: 文字の読み取り（Vision）と解析（ルール） | 済 | 済（[OCR評価] 15枚、下限あり） | 一部 | 合計・日付を実機で確かめたのは記録で9〜10枚 |
| レシート: 端末内AIの補助 | 済 | 合流の決まりだけ（作り物の答え） | **未（AIが動く端末で一度も動いていない）** | 4-4（D7） |
| レシート画像の保存 | 済 | 済 | 済（T-012） | iCloud から消すのに失敗したとき、やり直さない（5-4 の M3） |
| 覚えた店（T-008） | 済 | 一部 | 未 | |
| 版の表示（T-024） | 済 | 済 | 未 | |
| Privacy Manifest の理由つきAPI | **済（PR #52）** | 済（`PrivacyManifestTests`） | — | 配信のあと、Apple から申告漏れのメール（ITMS-91053）が来ないかで確かめる |

### 2-3. 古い文書・気づいたこと

| 文書 | 古い記述・気づいたこと | 実際 | 直す人 |
| --- | --- | --- | --- |
| `Docs/requirements.md` F11・F12・N1・N3、`Docs/safety.md` の約束1・3 | 「Production スキーマ登録が残り」「招待した相手だけが読める場所」 | 改訂案は `Docs/REQUIREMENTS_SAFETY_PROPOSAL.md`（約束の文は残し、現状を書き足す案） | 利用者（AIは書き換えない） |
| `Docs/TEST_PLAN.md` P0 の4 | 「合言葉を知らない Apple Account からアクセス不能」 | 合言葉が無くても、共有のURLを知っていれば入れる | Claude |
| `Docs/APP_STORE_METADATA.md` | 「招待したパートナーとだけ」「参加したふたりだけが読み書き」「レシート画像は外に出さない」 | **2026-10-22 に原稿を直した**（5-3）。共有の言い方は D1 のあと見直す | Claude（原稿）→利用者（入力） |
| `Docs/ARCHITECTURE_AND_RISK.md`・`Docs/roadmap.md` | 済んだことが「未」のまま | どれも済み | Claude |
| アプリの「データとプライバシー」 | 「正式公開前に…公開用プライバシーポリシーURLが必要です」 | 開発用のメモが利用者に見えている | Claude（R2。ポリシーのURLが決まってから） |
| `.github/workflows/ios-dev-build.yml` | 「Development 環境につながるビルド」 | **Bundle ID が本番と同じ。日常の端末には入れられない**（`Docs/TEST_APP_PLAN.md`） | Claude（文面の承認のあと） |
| この計画の前の版の付録A B3 | 「iCloudから戻す」 | 画面の言葉は「以前の家計簿を取り戻す」（はじめの画面）。付録Aを直した | Claude（この PR） |
| `Docs/SHARING_SECURITY_AUDIT.md` 10章 | 実機の手順に「アプリを削除 → 入れ直す」「iCloudから戻す」 | 日常の家計簿で行わない項目と、テスト用アプリ・3つ目の Account が要る項目を冒頭に書き、画面の言葉を直した | Claude（この PR） |
| `Docs/CLOUDKIT_SHARE_SCHEMA.md` | Ad Hoc 版は「TestFlight 版と同じアプリとして上書き」「データは消えません」 | 2026-09-28 に誤りと分かっていた。日常の端末に入れない注意を冒頭に足した | Claude（この PR） |
| リポジトリ | **公開（public）** | `FutariKakeiboTests/ReceiptCorpus.swift` に実際のレシートの写し（店名・住所・日時・金額。カード番号・担当者名などは置き換え済み）があり、誰でも読める。非公開にするのは利用者の判断（`Docs/safety.md` で承認が要る操作）。非公開にすると GitHub Actions の無料の範囲が変わり、いまの頻度で CI を回せなくなるおそれがある（GitHub の料金の説明はこの環境から読めず、未確認） | 利用者 |

---

## 3. 共有とデータ保全（優先順位1）

前提の監査は `Docs/SHARING_SECURITY_AUDIT.md`（T-040・T-041）、移す計画は `Docs/SHARING_MIGRATION_PLAN.md`（T-048）、
**D1 の設計は `Docs/SHARING_REVOCATION_DESIGN.md`**。

### 3-1. 第三者が参加できる条件（いま）

- `CloudKitSyncService.sharePublicPermission = .readWrite`。共有（CKShare）は**共有のURLを知っている人なら誰でも参加でき、読み書きできる**
- 参加の入口は2つ: (a) 合言葉（8文字、31文字から暗号用の乱数で、24時間）→ 公開データベースの `invite-<合言葉>` から共有のURLを引く。(b) 共有のURLそのもの
- 参加できる人: 使われる前の合言葉を期限内に知った人（先着1人）／**共有のURLを知っている人（期限なし。共有が続くかぎり）**／作った人・参加した人の Apple ID に入れる人
- 公開データベースは開発者が CloudKit Console で読める。合言葉のレコードには共有のURLが入る（5-2）
- 約束の言い方は **D1 が決まるまで確定しない**（D12）。改訂案は `Docs/REQUIREMENTS_SAFETY_PROPOSAL.md`

### 3-2. 合言葉の1回利用と期限（コードで確かめた）

| 守り | 仕組み | 自動テスト | 限界 |
| --- | --- | --- | --- |
| 1回だけ | 参加する前に `invite-used-<合言葉>` を作る。同じ名前は1つしか作れないので先着1人（`claimInvite`） | `SharingSafetyTests` | 共有のURLを直接読めば、アプリの確認を通らない |
| 期限 | 24時間（`ShareInvite.lifetime`）。アプリが比べる（`resolveInvite`） | 同上 | 端末の時計をずらすと通せる（1回の印は効く） |
| 後片付け | 使われた・期限切れの合言葉を、発行した端末が共有の画面を開いたときに消す（`tidyIssuedInvites`） | 同上 | 開かなければ残る。使われた印は消していない（5-4 の M4） |

### 3-3. 共有をやめたとき・共有し直したとき（D1）

| 条件（D1） | いま | 根拠 |
| --- | --- | --- |
| 1 共有をやめると以前の参加者が入れない | 仕組みはある。**画面では、ふたりより多いときだけ**ボタンが出る。参加した側が抜ける操作は無い | `stopSharing`・`SharingView.membersCard` |
| 2 共有し直しても古いURLだけでは入れない | **満たさない** | Apple（CKShare.url）: "This URL is stable and persists across shares and reshares of the same root record." |
| 3 データを失わない | 自動テストで押さえている。実機は未確認 | `RejoinSnapshotTests`・`SyncMergeTests` |

推奨（詳しくは `Docs/SHARING_REVOCATION_DESIGN.md`）: **公開前に、新しく作る共有を名指しの形にする。**
加え方は A2（ユーザーレコードIDで名指し）→ A1（一度きりのURL、作る側に iOS 26）→ A3（Apple の共有の画面）の順に、テスト用アプリで確かめて選ぶ。
いまの家計簿（利用者とパートナー）はパートナーが一度外れて入り直す必要がある（外さずに変える方法は Apple の資料に無い）。本番での切り替えは、リハーサルのあと改めて承認をもらう。

### 3-4. 参加者の確認

- 共有の画面に参加している人（名前は iCloud が教えてくれるときだけ）と人数。ふたりより多ければ赤字で知らせる（`strangerCount`）
- 名指しの形（A2）にすると、作った人の端末が加えるまで入れない。誰の申し込みかを確かめる仕組み（両方の画面に同じ確認番号を出すなど）を足せる

### 3-5. 既存の利用者を安全に移す方法

- 公開前なら、移すのは利用者とパートナーの家計簿だけ。テスト用アプリでリハーサル（`Docs/SHARING_REVOCATION_DESIGN.md` 6章 V8）してから
- 移す前の条件: `ShareMigrationReadiness`（作った人の端末・5分以内に同期済み・送信待ちのレシート画像が無い）。CI確認済み、画面からはまだ使わない

### 3-6. 未同期データの保護と、移行に失敗したときの復旧

- 同じ家計簿に入り直すときは置き換えずに突き合わせ、手元にしか無い記録・削除印・送信待ちのレシート画像・新しい設定を残す（`AppStore.snapshotAfterJoining`・`isSameHousehold`）。CI確認済み、実機は未
- 移行に失敗したら、公開の権限を戻す（同じURLで、いまと同じ形に戻る）。家計のデータは作った人の iCloud に残る

### 3-7. 復元と同期の場面

| 場面 | 仕組み（コード） | 自動テスト（CI） | 実機 | 言えないこと |
| --- | --- | --- | --- | --- |
| 作った人・参加した人の入れ直し | はじめの画面の「以前の家計簿を取り戻す」。2つ以上あれば選ぶ（`RecoveryCandidate`） | `testAnEmptyPhoneTakesEverythingFromICloudAndPushesNothing` ほか | 未（付録A B3） | iPhone の中だけの家計簿は戻らない。消す前に送れていなかった記録も戻らない |
| 別の Apple ID の2台で共有 | CKShare（公開の権限） | `SharingSafetyTests` ほか | **済**（2026-10-04） | — |
| オフラインで記録したあとの同期 | 手元に保存し、戻ったら iCloud に無い・新しい記録と削除印を送り直す | `testAfterBeingOfflineOurNewExpensesArePushedAndTheirsArrive`、**`testAnAdditionThatDidNotReachICloudIsSentOnTheNextSync`・`testADeletionThatDidNotReachICloudKeepsItGoneAndIsSentOnTheNextSync`（追加）** | 未（付録A A2） | 送るまで相手には見えない |
| 同時編集（D10: 初回は受け入れる仕様） | **後から直したほうが丸ごと残る**（直した時刻。項目ごとに混ぜない） | `testWhenBothEditedTheNewerEditWinsAndTheOlderIsNotPushedBack` ほか | 未（A4） | 負けた側の直しは知らせずに消える。時計が大きくずれると古い直しが勝つ |
| **D10 必須: 削除した記録が戻らない** | 削除印は時刻を比べずに勝ち、消さずに残す。iCloud 側も削除印のあるレコードを上書きしない（`CloudKitSyncService.mayOverwrite`） | `testADeletionFromTheOtherPhoneBeatsAnOlderPhonesLaterEdit`、**`testADeletionAndAnOfflineEditAndAdditionOnTheOtherPhoneSettleSafelyInEitherOrder`・`testTheUploadNeverOverwritesADeletionEvenWithANewerEdit`・`testRejoiningDoesNotBringBackWhatTheOtherPhoneDeletedWhileWeWereOut`（追加）** | 未（A3） | — |
| **D10 必須: 別々に足した記録が失われない** | 記録ごとのIDで突き合わせ、片方にしか無いものは残して送る | `testAfterBeingOfflineOurNewExpensesArePushedAndTheirsArrive`、**`testTwoPhonesThatAddedDifferentExpensesOfflineBothEndUpWithBoth`（追加。同期の順を両方試す）** | 未（A2） | — |
| 共有への入り直しで未同期データが消えない | 3-6 | `RejoinSnapshotTests` | 未（B2） | — |
| 復元後も本人と相手を取り違えず、精算が正しい | 戻った側で「自分」が決まる。精算は支出ごとの支払った人で計算 | `testTheMemberOnThisPhoneFollowsTheSideItCameBackFrom`・`LedgerCalculatorTests` | 未（B3） | 取り違えると、新しい支出の「支払った人」の初期値が相手になる |

---

## 4. 無料のレシート読み取り（優先順位2）

### 4-1. いまの作り（コードで確かめた）

- **文字の読み取り:** Vision（`VNRecognizeTextRequest`、revision 3、accurate、ja-JP・en-US、言語の補正あり）。端末の中だけ
- **解析:** ルール（`ReceiptParser`。候補と点数、足し算での照合、店と品の辞書、覚えた店）。ここまではすべての端末で動く
- **AI補助:** `ReceiptInterpreter` が、iOS 26 以降で `SystemLanguageModel.default.availability` が available の端末だけ、同じ文字を端末内のモデルに読ませ、答えの取れた項目だけ差し替える。
  根拠のある値（合計の語・辞書の店名・品の値段の重さで決めた種類）は上書きしない。足し算と食い違う合計、ありえない日付は捨てる。
  モデルが答えないとき・失敗したときはルールの結果のまま。**呼び出しに時間の上限は無い**
- **AIが使えない端末:** ルールの結果のまま。利用者の iPhone 13・SE2 はこちら
- **合計と日付:** 合計に根拠が無い・足し算と合わないときは「合計金額をレシートと見比べてください」。日付が読めないときは入力を促す。**範囲の中での読み違いには目印が無い**（保存前に画面で確かめてもらう）
- **通信:** レシートの認識のための通信は無い（`URLSession` も http も無い）。アプリ全体の通信は CloudKit（iCloud）だけ
- **ログ:** `print` を出す処理はすべて `#if DEBUG` の中。配信するビルドには出ない

### 4-2. 確かめた範囲

| 項目 | CI | 実機 |
| --- | --- | --- |
| 解析（実物15枚: 実機の読み取り結果2枚・写真から組み直した13枚） | 合計 15/15・日付 15/15・店名 14/15・種類 14/15・明細 71/71。下限は `ZReceiptScoreboardTests.floors` | — |
| AIが使えない端末で、撮ってから保存まで | — | これまでの実機の確認はすべてこの道。合計・日付を確かめたのは記録で9〜10枚（要件の完成条件4は10枚以上） |
| ローソン・PISOLA を直した版（T-039） | 済 | 未 |
| AIが使える端末 | 合流の決まりだけ（作り物の答え） | **未** |

### 4-3. PR #29 は公開版に取り込まない（D11 で決定）

- 2026-09-06 のコードから分かれていて、合言葉の発行を直す前の方式に戻してしまう。OCRの診断を公開版の読み取りのたびに出す
- 共有エラーの診断（処理名とエラーの番号だけ）の考え方は良い。要るなら、TestFlight のビルドだけで出す形に作り直す（公開後でよい）

### 4-4. AIが動く端末での確かめ（D7）

確かめる方法:

| 方法 | 要るもの | 承認・手間 | 本番の家計簿への影響 |
| --- | --- | --- | --- |
| 対応端末を借りて、テスト用アプリ（Ad Hoc）を入れる | Apple Intelligence に対応した iPhone（iPhone 15 Pro 以降など。Apple の対応表で確かめる）の持ち主の協力。その端末の UDID の登録。テスト用アプリ（D8）が先に要る | 持ち主の同意。UDID を登録する（Apple Developer の端末の一覧に残る） | 無い（レシートの読み取りは iCloud なしでも動く） |
| 協力者を内部テスターにする（TestFlight） | 協力者を App Store Connect の利用者に加える。個人の登録でも加えられる（"If you're enrolled in the Apple Developer Program as an individual, you can give up to 50 additional users access to your content in App Store Connect."）。内部テスターは "App Store Connect users with access to your content" | **利用者の承認**（App Store Connect の利用者を加える）。役割は最小にし、このアプリだけに絞る | 協力者は自分の家計簿で試す（合言葉を使わなければ利用者の家計簿に触れない） |
| 協力者を外部テスターにする（TestFlight） | 最初のビルドは TestFlight の審査（"The first build you submit requires a full review"） | **外部テスターは、その都度利用者の承認**（Claude の範囲の外） | 同上 |
| CI のシミュレータ | — | — | 代わりにならない（実機のモデルではない。GitHub の macOS ランナーで使えるかも未確認） |

確かめられない場合の比べ（Vision とルールでの読み取りは、どちらでも変わらない）:

| | 公開版で AI補助を有効のまま（確かめずに） | 公開版では一時的に止める |
| --- | --- | --- |
| だれに効くか | iOS 26 以降で Apple Intelligence が使える iPhone の人だけ。**審査の担当者の端末が対応機種のこともありうる** | 同じ人たち |
| 良くなりうること | 読みにくいレシートで、店名・種類などが埋まる（どれだけ良くなるかは測れていない） | — |
| 悪くなりうること | 待ち時間（上限が無く、何秒かかるか未確認）。根拠の無い項目に違う値が入る（根拠のある値は上書きしない作り） | 対応端末の人も、ほかの端末と同じルールの読み取りになる（[OCR評価] の15枚で合計 15/15・日付 15/15） |
| 戻し方 | 不具合が出たら、更新を出すまで直らない | 確かめたら次の更新で戻す（コードとテストは残す） |

**推奨: 公開までに対応端末で確かめられなければ、公開版では一時的に止める。** 看板の機能の待ち時間と結果に、確かめていない処理が関わるため。
止めても、ほとんどの利用者（AIが使えない端末）の動きは変わらない。決めるのは利用者（止めるならコードの1か所とテストで行う）。

---

## 5. App Store 公開の準備（優先順位3）

### 5-1. 完成済み・不足・本人の判断

| 項目 | 状態 | 根拠 | 作業 |
| --- | --- | --- | --- |
| 公開プライバシーポリシー・運営者名・問い合わせ先 | **原稿あり（本人の情報待ち）** | `Docs/drafts/privacy-policy.md`。審査 5.1.1(i) は App Store Connect とアプリの中の両方にリンクを求める | D3・R1 |
| サポートURL | **原稿あり（本人の情報待ち）** | `Docs/drafts/support.md`。App Store Connect の必須項目 | D3・R8 |
| アプリの中のポリシーへのリンク | **不足** | 「データとプライバシー」にリンクが無く、開発用のメモが出ている（審査 2.1(a)）。URL が決まってから。アプリのソースにURLを入れると `scripts/check_all.sh` の通信先の検査に当たるので、そのURLだけ許す形に直す | R2 |
| Privacy Manifest の理由つきAPI | **済（PR #52）** | UserDefaults `CA92.1`、ファイルの日時 `C617.1`。コードを検索して、使っているのはこの2つだけ | R3 |
| Privacy Manifest の収集データと App Privacy の回答 | **D1 で決まる（条件付き）** | `Docs/PRIVACY_POLICY_REQUIREMENTS.md`。いまの plist はどちらの案とも合っていない | D2・R3・R4 |
| 使用している SDK | 完成済み | 外部のライブラリは無い。Apple のフレームワークだけ | — |
| 説明文・キーワード・カテゴリ | 原稿あり（直しが要る） | `Docs/APP_STORE_METADATA.md`。言い方は 5-3 | R5 |
| 年齢区分 | **不足（本人）** | 2026-01-31 から、新しい年齢区分の質問への回答が要る | R8 |
| スクリーンショット | **案あり（承認待ち）** | `Docs/SCREENSHOT_PLAN.md`。必須は Dynamic Island の medium（1206 × 2622 など）と large（1320 × 2868 など） | D9・R9 |
| 審査メモ | 原稿（付録B。2026-10-22 に言い方を直した） | 審査 2.3.1(a) | R8 |
| 対応端末 | 完成済み | iOS 17 以降の iPhone | — |
| 配信する国 | **決定: 日本だけ**（D5） | EU のデジタルサービス法の申告は要らない | R8 |
| 公開のしかた | **決定: 手動でリリース**（D13）。審査への提出と、通過後の一般公開は、それぞれ利用者が確かめて決める | — | R8 |
| 版 | **決定: 次の配信から 2.0.1**（D6。5-5） | — | — |
| 文字の拡大 | 一部 | 固定の大きさが17か所 | R10 |
| VoiceOver | 一部 | 読み上げの指定は一部の画面だけ | R7 で確かめる |
| 通信に失敗したときの表示 | 完成済み（実機は未） | 「同期できませんでした」など | R7 |
| Apple の SDK・最低OSの要件 | 満たしている | Xcode 26・iOS 26 SDK（CI は Xcode 26.6）。iOS 13 以上 | — |
| 輸出の暗号の申告 | 完成済み | `ITSAppUsesNonExemptEncryption = false` | — |
| iCloud のデータの消し方（ポリシーに書く） | **不足（対策の提案あり）** | 5-4 | D14・R17 |

### 5-2. 「開発者は家計データを読めない」と言えるか（D2）

詳しくは `Docs/PRIVACY_POLICY_REQUIREMENTS.md`。利用者の指示どおり、2つを分けて書く。

| 問い | いま | 名指しの共有にしたあと |
| --- | --- | --- |
| 開発者がデータベースを直接見られるか | **見られない**（CloudKit Console で見られるのは開発者自身の iCloud の分だけ） | 見られない |
| 開発者が招待の情報から共有に参加して見られるか | **見られる。** 合言葉のレコードに共有のURLが入っていて、開発者は公開データベースを読め、URLだけで参加できる | 見られない（作った人が加えないと入れない。一度きりのURL（A1）なら、使われる前のものの分だけ残る） |
| App Privacy の申告 | User ID・Other Data に加え、家計のデータも申告する側に倒す | **User ID**（公開データベースの記録に付く作成者のID）と **Other Data**（招待の共有URL。暗号にして置けば外せる） |

### 5-3. 掲載の言い方（2026-10-22 に `Docs/APP_STORE_METADATA.md` へ反映した）

| いま（`Docs/APP_STORE_METADATA.md`） | 直す案 | 理由 |
| --- | --- | --- |
| 「招待したパートナーとだけ安全に共有できます」 | 「合言葉で、相手と同じ家計簿を使えます。参加している人は画面で確かめられます」 | URLを知っている人も参加できる（3-1） |
| 「家計簿に参加したふたりだけが読み書きできます」 | 「家計のデータは、家計簿を作った人の iCloud に置き、共有に参加した人と同期します」 | 同上 |
| スクリーンショット5「招待したパートナーだけと共有」 | 「合言葉で、ふたりの家計簿に」 | 同上 |
| スクリーンショット6「レシート画像は外に出さない」 | 「レシートを撮ると、合計と日付を読み取ります」 | 画像は保存がONのとき iCloud（共有先）にも置く |
| （無い）初期ユーザーの特典 | **初回の掲載では書かない。** いま無料で使えることだけを正確に伝える（D4） | 特典は未定。審査 2.3.7「Metadata such as app names, subtitles, screenshots, and previews should not include prices, terms, or descriptions that are not specific to the metadata type.」 |

スクリーンショットは架空データで作る（`Docs/SCREENSHOT_PLAN.md`）。実際の家計や個人情報を載せない。

### 5-4. 削除の対策（D14。公開前の提案）

いまの代わりの手順（iPhone の設定・アプリの操作）でできること・できないことは `Docs/PRIVACY_POLICY_REQUIREMENTS.md` の削除の表。
**要る削除ができないので、公開後の対応と決めつけず、公開前に次を入れることを提案する。** どれも本番の家計簿では試さず、テスト用アプリで確かめる。

| # | 対策 | 直すこと | 大きさ | 確かめ方 |
| --- | --- | --- | --- | --- |
| M1 | 作った人が、いつでも「共有をやめる」 | いまは「ふたりより多いとき」だけ出るボタンを、作った人にはいつも出す（相手も入れなくなることを確認の文で伝える） | 小（仕組みはある） | 文言のテスト、テスト用アプリ |
| M2 | 参加した人が「この家計簿から抜ける」 | 参加者が共有を消すと、その人だけ外れる（Apple: "If a participant attempts to delete the share, CloudKit removes the participant. The share remains active for all other participants."）。抜けたあと手元の写しを残すか消すかを選べるようにする | 中 | テスト用アプリ |
| M3 | 消した記録の中身を iCloud からも消す | 削除印には ID・削除した時刻・親だけを残し、金額・店名・メモなどを空にする。レシート画像の削除に失敗したら、あとでやり直す | 小〜中（削除印の決まりは変えない。古い版も削除印を先に見るので読める） | 自動テスト、テスト用アプリ |
| M4 | 公開データベースの後片付け | 参加した人の端末が、自分の「使われた印」を期限のあとに消す。作った人の端末が、期限切れの合言葉をアプリを開いたときにも消す。「このiPhone内のデータを削除」の前に、発行した合言葉を消す | 小 | 自動テスト、CloudKit Console（テスト用コンテナ） |
| M5 | 作った人が「iCloud の家計簿を消す」 | 家計簿の置き場所（ゾーン）ごと消す。相手も見られなくなる | 中 | テスト用アプリ。**設定からの削除が作った人の家計簿を確実に消すと確かめられたら、M5 は要らない** |

決めること: どれを公開前に入れるか（推奨は M1〜M4。M5 は設定からの削除の確かめ次第）。

### 5-5. 版の付け方（D6。2026-10-22 決定）

- いま配信済みの 2.0.0 は変えない。**次に新しい更新版を配信するときから 2.0.1 → 2.0.2 → 2.0.3** と末尾を1つずつ上げる
- 上げるのは、新しい更新版を TestFlight などへ配信するとき（コミットやテストのたびではない）
- 同じ版のビルドが失敗してやり直すときは上げない
- 確かめた同じビルドを App Store の審査・公開へ進めるだけなら上げない
- アプリの中の版の表示（設定の一番下）は `CFBundleShortVersionString` から読む（`AppVersion`）ので、配信の版と同じになる
- ビルド番号は別に、ワークフローが時刻から作る（年.月日.時分。同じ版の中で重ならず、前より大きい）
- 2.0.0 より下には戻さない（TestFlight に 2026-09-01 の事故の 1.0 が残っている。T-033）
- 配信の手順（`.claude/skills/release/SKILL.md`）の改訂案は付録C。**書き換えは文面の承認のあと**

---

## 6. 初期ユーザーの無料特典（D4。いまは何も作らない）

方針（2026-10-22 決定）: 初期ユーザーを優遇する方針は続ける。対象・期間・回数は未定。「永久無料」などの約束はしない。
**初回の掲載では、いま無料で使えることだけを伝え、決まっていない特典は告知しない。** 課金はまだ作らない。

### 6-1. Apple の AppTransaction で確かめたこと・確かめていないこと

| 場面 | 資料で確かめたこと | 確かめていないこと |
| --- | --- | --- |
| 無料のアプリ | originalAppVersion: "Use this value to determine which app version the customer first purchased or downloaded."／appTransactionID: "The App Store generates a single, globally unique appTransactionID for each Apple Account that downloads your app" "The appTransactionID is available even if a customer makes no Apple In-App Purchases." | — |
| 入れ直し | originalPurchaseDate: "The original purchase date remains the same, even if the customer deletes and reinstalls the app." | — |
| 機種変更（同じ Apple Account） | appTransactionID: "This value remains the same for the same Apple Account and app if the customer redownloads the app on any device" | originalPurchaseDate が別の端末でも同じか（明記は入れ直しだけ。同じになる見込み） |
| Apple Account を変えた | appTransactionID は Apple Account ごと → 別の人として扱われる | — |
| TestFlight と本番 | "Apps that you download from TestFlight always run in the sandbox environment." サンドボックスでは originalPurchaseDate は常に 2013-08-01、originalAppVersion は常に "1.0" | TestFlight で使っていた人が App Store の版を入れたとき、originalPurchaseDate が App Store で入手した日になるか（なる見込み） |
| 取れないとき | AppTransaction.shared: "This property throws an error if the AppTransaction isn't available or if the user isn't authenticated with the App Store. Getting an AppTransaction may require network connectivity." | — |
| App Store と iCloud で Apple Account が違う人 | — | 判定は App Store の Account、家計簿の共有は iCloud の Account。違う人の扱いは決めごと（未確認） |

### 6-2. 後から見分けられなくなる設計上の問題（確かめた結果）

1. **Bundle ID と App Store のアプリの登録を変えない**（AppTransaction はアプリごと）。テスト用アプリ（D8）は別の Bundle ID だが、App Store には出さない
2. **版の文字のまま比べない。** Apple の iOS の例は `originalAppVersion < "2"` と文字で比べている。このアプリのビルド番号は `2026.1022.404` の形で、文字のまま比べると `2026.1022.404` が `2026.1022.42` より前と判定される。
   **判定は originalPurchaseDate（日付）で行い、版で行うなら要素ごとに数として比べる**
3. ビルド番号の形（年.月日.時分）を変えない。小さな整数（`1`、`2`…）に戻すと、後のビルドが前より小さく見える
4. 初めて公開した日・版・ビルド番号を記録する（6-3）
5. 取れないとき（通信なし・App Store にサインインしていない）は「不明」として扱い、特典を外さない作りにする（課金を作るとき）

→ いま課金のコードは要らない。上の5つを守れば、後から判定できる見込み。

### 6-3. 初回公開の記録（公開したときに埋める）

| 項目 | 値 |
| --- | --- |
| 審査に出した日 | 【】 |
| App Store で公開した日（日本時間） | 【】 |
| 版 | 【】 |
| ビルド番号 | 【】 |

---

## 7. AI家計評価（公開後。T-058。いまは作らない）

- いまは実装しない。外部AIとの契約・API連携・バックエンドの構築もしない
- 使える土台: `MonthlyReport`、`LedgerCalculator`。集計した値は端末の中で作れる
- 公開後に、幅広い端末で使える方式を、品質・費用・プライバシーで比べる:

| 方式 | 端末 | 品質 | 費用 | プライバシー |
| --- | --- | --- | --- | --- |
| ルールによる評価（集計から決まった言い方を選ぶ） | すべて | 単調だが正確 | 無し | 端末の中だけ |
| 端末内AI | Apple Intelligence の端末だけ | 端末による | 無し | 端末の中だけ（利用者は魅力を感じていない） |
| 外部AI（集計した値だけを送る） | すべて | 高い見込み | 回数ごとにかかる。APIキーをアプリに入れられないので中継のサーバーが要る | **送る前に、下の項目を決める** |

外部へ送るなら、コードより先に決めること: 送る項目、送り先、保存と学習への利用、**2人分の情報への同意**、ポリシーの改訂、App Privacy の申告の変更、
審査 5.1.2(i)（「You must clearly disclose where personal data will be shared with third parties, including with third-party AI, and obtain explicit permission before doing so.」）、費用と課金の関係。

---

## 8. 作業の一覧（優先順位・完了条件・確認方法）

### P0: 公開前に必須

| ID | 作業 | 担当 | 完了条件 | 確認方法 |
| --- | --- | --- | --- | --- |
| R1 | プライバシーポリシーを公開する | Claude（原稿は済）→ 利用者（氏名・メール・掲載先の承認・確認） | 公開URLで読める。必須15項目と App Privacy の回答がそろう | URLを開き、表と突き合わせる |
| R2 | アプリの中にポリシー・問い合わせ先へのリンクを置き、開発用のメモを消す | Claude | 「データとプライバシー」から開ける。メモの文が無い | CI ＋ 実機 |
| R3 | Privacy Manifest: 理由つきAPI（**済**）、収集データを D2 の決めた列に合わせる | Claude | plist、CI 緑、配信のあと申告漏れのメール（ITMS-91053）が来ない | CI、利用者のメール |
| R4 | App Privacy の回答（App Store Connect） | 利用者（Claude が回答の表を作る） | R3・ポリシーと同じ内容 | 画面の照合 |
| R5 | 掲載文・スクリーンショットの見出しを直す | Claude（原稿）→ 利用者（入力） | 5-3 の言い方。価格・条件・特典を入れない | 原稿と入力画面の照合 |
| R6 | 共有の方式をそろえる言い方（アプリ・掲載・ポリシー・要件） | Claude（D1 のあと） | どこも同じ言い方 | 文言のテスト、照合 |
| R7 | 公開前の実機確認（付録A） | 利用者。Claude は手順と記録 | 付録A がすべて合格か、未確認の理由が書いてある | 結果の報告 |
| R8 | App Store Connect の入力（サポートURL・年齢区分・カテゴリ・日本だけ・手動でリリース・無料・審査メモ） | 利用者（Claude が原稿） | 提出の画面に警告が無い | 利用者の画面 |
| R9 | スクリーンショット（架空データ） | Claude（D9 の承認のあと）→ 利用者（確かめて入力） | 必要な大きさがそろい、実在の情報が無い | 目で確かめる |
| R16 | **共有を名指しの形にする（D1）** | Claude（検証と実装）→ 利用者（方式・移行の承認） | `Docs/SHARING_REVOCATION_DESIGN.md` の V1〜V9 が合格し、新しい共有が名指しになる。いまの家計簿の移行は別の承認 | テスト用アプリ、CI |
| R17 | **削除の対策（D14。M1〜M4、M5 は確かめ次第）** | Claude → 利用者（どれを入れるか） | 5-4 の確かめ方で合格し、ポリシーに確かめた手順だけを書く | CI、テスト用アプリ |
| R18 | **テスト用アプリを作る（D8）** | 利用者（Apple Developer の変更）＋ Claude（ワークフロー・コード。文面の承認のあと） | 日常の家計簿と並べて入り、テスト用コンテナにつながる | ワークフローの権限の確かめ、実機 |

### P1: 公開前に強く勧める

| ID | 作業 | 担当 | 完了条件 | 確認方法 |
| --- | --- | --- | --- | --- |
| R10 | 文字の拡大: 一覧の金額など読む文字を、拡大に追従させる | Claude | CI 緑。最大の文字でも主要な画面が読める | 実機（A7） |
| R11 | AIが動く端末で読み取りを確かめる（D7） | 利用者（端末か協力者） | 5枚以上で合計・日付が、AIが使えない端末と同じか良い。できなければ公開版では止める（推奨） | 結果の報告 |
| R12 | レシートの実機確認を10枚に。ローソン・PISOLA（T-039） | 利用者 | 10枚で合計・日付が正しい | 記録 |
| R13 | 精算のテストを足す | Claude | CI 緑 | CI |
| R14 | 古い文書を直す（2-3）。requirements.md・safety.md は改訂案（済。利用者が直す） | Claude（＋利用者） | 2-3 の表が片付く | 差分 |

### P2: 公開後でよい

| ID | 作業 | メモ |
| --- | --- | --- |
| R20 | （R16 に移した） | 2026-10-22、公開前を推奨に変えた |
| R21 | 同時編集で負けた側に知らせる（または項目ごとに混ぜる） | D10 で初回は受け入れた |
| R22 | （5-4 の M5 に移した） | — |
| R23 | TestFlight だけで出す診断（PR #29 の代わり） | 要るときだけ |
| R24 | 初期ユーザーの特典・課金の実装 | 6章を決めてから |
| R25 | AI家計評価（T-058） | 7章 |

### 進め方（目安）

1. **いま（Claude、この回）:** R3 の理由つきAPI、D10 のテスト、R1・R5・R8・R9 の原稿と案、D1・D8・D14 の調査と設計。CI → マージ（包括承認の範囲）。**TestFlight への配信はこの回はしない**（見た目の変化が無く、実機の確かめに使っているビルドを入れ替えないため。次の配信は 2.0.1）
2. **利用者:** 9章の「まだ判断が要る」項目、テスト用アプリのための Apple Developer の変更、付録A の A（いまの端末）
3. **Claude:** テスト用アプリ（R18）→ 名指しの共有の検証と実装（R16）→ 削除の対策（R17）→ 配信（2.0.1〜）
4. **利用者:** テスト用アプリでの確かめ（付録A の B）、ポリシーの公開（R1）、App Store Connect の入力（R4・R8・R9）
5. **提出・公開:** 審査への提出と、通過後の一般公開は、それぞれ利用者が確かめて決める（D13）

---

## 9. 利用者の回答（D1〜D14）の整理（2026-10-22）

| # | 項目 | 区分 | 決まったこと | 残っていること・推奨 |
| --- | --- | --- | --- | --- |
| D1 | 共有の方式 | **追加調査** | 説明を実装に合わせて正確にする。古いURLが共有し直したあとにまた使えるリスクは**承認していない**。本番の共有の権限の変更・移行は未承認 | 名指しの共有を公開前に（推奨）。方法は A2 → A1 → A3 の順にテスト用アプリで確かめる（3-3） |
| D2 | App Privacy | **条件付き** | User ID の申告を基本にする。項目ごとに理由を残す | D1 で2通りに分かれる（5-2）。名指しにすれば User ID と Other Data（招待の共有URL）だけ |
| D3 | 運営者情報・掲載先 | **本人の情報待ち** | 法人なし。個人の開発者として準備。架空の情報を入れない。個人の情報を含む公開は、完成した原稿を利用者が確かめてから | 氏名の書き方と専用のメール。掲載先の推奨は GitHub Pages（公開用の別リポジトリ）。販売者名とポリシーの運営者名は `Docs/drafts/README.md` |
| D4 | 初期ユーザーの特典 | **決定済み** | 優遇の方針は続ける。対象・期間・回数は未定、約束しない。初回の掲載は「いま無料」だけ | 公開した日・版・ビルド番号を 6-3 に記録する。判定は日付で（6-2） |
| D5 | 配信する国 | **決定済み** | 日本だけ | — |
| D6 | 版 | **決定済み** | 次の配信から 2.0.1 → 2.0.2 …（5-5） | 配信の手順の改訂（付録C）は文面の承認待ち |
| D7 | AIが動く端末での確かめ | **追加調査** | 推測で検証済みにしない。いまの AI補助をすぐ撤去する指示ではない | 確かめる方法は 4-4。確かめられなければ公開版では一時的に止める（推奨）。決めるのは利用者 |
| D8 | テスト用の端末 | **条件付き** | 専用の2台・2つの Apple Account は使わない。本番と分けたテスト用アプリを調べる | 同じ端末に並べられる見込み（`Docs/TEST_APP_PLAN.md`）。Apple Developer の変更とワークフローの承認が要る |
| D9 | スクリーンショット | **条件付き** | CI のシミュレータで架空データ。価格・特典を入れない | 画面と見出しの案（`Docs/SCREENSHOT_PLAN.md`）とワークフローの承認待ち |
| D10 | 同時編集 | **決定済み** | 同じ記録は後の編集が勝つ（初回）。消した記録が戻らないこと・別々の追加が失われないことは必須 | 自動テストを足した（3-7）。実機は付録A |
| D11 | PR #29・#28 | **決定済み** | #29 は公開版に取り込まない。#28 は初回公開の必須に入れない。閉じる・ブランチを消すことはしない | — |
| D12 | requirements.md・safety.md | **条件付き** | 改訂案を先に出す。説明を変えることと安全の要求を下げることを分ける | 差分は `Docs/REQUIREMENTS_SAFETY_PROPOSAL.md`。約束の文は残し、現状を書き足す案。最終は D1 のあと |
| D13 | 公開のしかた | **決定済み** | 手動でリリース。審査への提出と、通過後の一般公開は、それぞれ利用者が確かめて決める | — |
| D14 | 削除 | **追加調査** | アプリの中の削除の機能を必須にしないのは、実行できる代わりの手順があることが条件 | 代わりの手順では足りない（5-4）。M1〜M4 を公開前に（推奨）。設定からの削除はテスト用アプリで確かめる |

---

## 付録A 実機での確かめ方（日常の家計簿で、削除・入れ直し・共有をやめることはしない）

**A はいまの端末で安全にできるもの。B は本番と分けたテスト用アプリが要るもの。C は3つ目の Apple Account か協力者が要るもの。**
端末やアカウントが足りないものも黙って省かない。できないときは「未確認」として残し、公開の判断に載せる。

### A. いまの端末で安全にできるもの（本番のアプリ。テスト用の支出だけを使い、最後に消す）

テスト用の支出は、店名を「テスト」、金額を 1円にする。試したあとは必ず消す。

| # | 手順 | 合格 |
| --- | --- | --- |
| A1 | 閉じているあいだの通知: Aで通知ON → ホーム画面に戻る（上にスワイプしない）→ Bで「テスト」1円を登録 | 数分のうちにAに通知（金額・店名なし）。押すとその支出が開く。最後にBで消す |
| A2 | オフライン: Bを機内モード →「テスト」1円を足す。同じころAでも「テスト」1円を足す → Bの機内モードを切ってアプリを開く | 2件とも両方に出る（別々に足した記録が消えない）。消すと両方から消える |
| A3 | 削除が戻らない: Bを機内モード → Aでテスト支出を消す → Bで同じ支出の金額を直して保存 → Bの機内モードを切る | Bからも消える（戻ってこない） |
| A4 | 同時編集: テスト支出をA・Bで開き、ほぼ同時に違う金額で保存 | 30秒ほどで、後から保存した金額にそろう。最後に消す |
| A5 | 精算: テスト支出を「2人で折半」で足す | 精算額が期待どおり動き、消すと元に戻る |
| A6 | レシート（AIが使えない端末）: 手元のレシートを撮る（保存しない） | 合計・日付が正しい。外れたら写真と「読み取った文字を確認」の画面を撮る |
| A7 | 文字を最大にして（設定 → アクセシビリティ → 画面表示とテキストサイズ → さらに大きな文字）、ホーム・追加・履歴・設定を見る。VoiceOver で支出を1件足す（足したら消す） | 読めない・押せない所が無い |
| A8 | 共有の画面で、参加している人の一覧を見る（見るだけ） | 2人が出る。赤字の警告が無い |

### B. 本番と分けたテスト用アプリが要るもの（`Docs/TEST_APP_PLAN.md`。いまの2台と2つの Apple Account）

| # | 手順 | 合格 |
| --- | --- | --- |
| B1 | 合言葉: Aで発行 → Bで参加。Aで2回続けて発行し、1回目をBで入れる | 1回目の合言葉は「見つかりませんでした」 |
| B2 | Aで「共有をやめる」→ 外れているあいだにBで支出を足し、消す → 新しい合言葉でBが入り直す | 足した支出は消えずにAへ届き、消した支出は戻らない（未同期のデータが残る） |
| B3 | 取り戻し: A（作った側）とB（参加した側）でテスト用アプリを消して入れ直し、はじめの画面の「以前の家計簿を取り戻す」 | 家計簿と支出が戻る。自分の名前が正しい。新しい支出の「支払った人」の初期値が自分 |
| B4 | 共有の方式の検証（`Docs/SHARING_REVOCATION_DESIGN.md` 6章の V1・V2・V4〜V9） | 各行の合格 |
| B5 | 削除: 設定 → iCloud → ストレージを管理 で「家計簿テスト」のデータを消す（作った側・参加した側で別々に） | 何が消え、相手と公開データベースに何が残るかを記録する（Development の環境なので、本番に当てはめるときは違いを書き添える） |
| B6 | レシート画像: 支出を消したとき iCloud からも消えるか。機内モードで消したとき残るか（M3） | 記録どおり |

### C. 3つ目の Apple Account か協力者が要るもの

| # | 手順 | 合格 | 用意できないとき |
| --- | --- | --- | --- |
| C1 | 3人目の参加: 使われた合言葉・使われた一度きりのURL（V3）で3人目が参加しようとする | 入れない | 未確認として残す |
| C2 | 3人目が参加したときの赤字の警告（いまの形のまま出す場合） | 警告が出て、作った人が共有をやめられる | 未確認として残す |
| C3 | 同じ Apple Account の別の iPhone で「以前の家計簿を取り戻す」（機種変更） | 同じ家計簿に戻る | 未確認として残す（同じ Account で入れる iPad などがあれば B として行える） |
| C4 | AIが動く端末での読み取り（4-4） | 合計・日付が、AIが使えない端末と同じか良い | 公開版では AI補助を止める（推奨） |

番号の対応: `Docs/SHARING_SECURITY_AUDIT.md` 10章、`Docs/NOTIFICATIONS.md` 5章。

---

## 付録B 審査メモの原稿（App Store Connect の「Notes for Review」）

2026-10-22 に、利用者の指摘で3つの言い方を直した（独自のアカウントは無いが共有には iCloud が要る／公開データベースは開発者が読める／
文字の認識は端末の中でも、保存した画像は iCloud に同期する）。アプリ全体の通信（CloudKit）と、レシートの認識のための送信（無い）を分けて書く。
【D1】【D7】は、その決定に合わせて最後に選ぶ。

```
Futari Kakeibo is a household budget app for two people. The app has no account system of its own.
Sharing between two people requires each iPhone to be signed in to iCloud.

Where data is stored:
- Before sharing starts, all data stays on the device.
- After sharing starts, household data and any receipt images the user chose to keep are stored in the
  creator's iCloud (CloudKit private database) and synced with the people who joined. The developer
  cannot browse this data.
- To invite the partner, the app stores an invitation record (the share's URL and an expiry time; CloudKit
  adds the creator's user record ID) in the app's CloudKit public database, which the developer can access.
  [D1, named sharing] This record alone does not let anyone join; the creator must add the person.
We do not operate our own servers. There is no advertising and no third-party analytics.

How to review sharing (two iPhones signed in to different Apple Accounts with iCloud are needed):
1. iPhone A: 設定 tab > 共有をはじめる > 合言葉を発行する. An 8-character code appears.
2. iPhone B: 設定 tab > 共有をはじめる > enter the code > この合言葉で参加する.
3. Add an expense on either iPhone (追加 tab). It appears on the other within about 30 seconds.
With a single iPhone, you can still issue a code and see the sharing screen.

Receipt scanning: 追加 tab > レシート > カメラで撮る. Text recognition runs on the device (Vision).
Receipt images and recognized text are not sent to any server for recognition. If the user keeps the
receipt image, a reduced copy is synced through iCloud as described above.
[D7, if kept] On devices with Apple Intelligence, the on-device model may help fill in fields; this also
runs on the device.

Notifications about the other person's new expenses are off by default (設定 tab > 通知).
They are created on the device after a silent CloudKit signal; they do not include amounts or store names.
```

画面の言葉は 2026-10-22 の main で確かめた（「共有をはじめる」「合言葉を発行する」「この合言葉で参加する」「カメラで撮る」）。
提出の前に、提出するビルドの画面と照らし合わせる。

---

## 付録C 配信の手順の改訂案（D6。`.claude/skills/release/SKILL.md`。**文面の承認のあと書き換える**）

`CLAUDE.md` の決まりで、指示ファイルを書き換える前に利用者の承認が要る。下の差分で承認をもらう。

```diff
 ## 1. 配信するコミットを決める
 
 - 送るのは **`main` だけ**。ワークフローが `main` 以外では `testflight` ジョブを動かさない（2026-10-14 から）
+- **前に配信した版のままなら、配信の前に版を上げる PR を出す**（下の「版とビルド番号」。2026-10-22 利用者が決定）
 - PR の head と、マージできるかを見る
```

```diff
 ## 版とビルド番号
 
 - **ビルド番号は何もしなくてよい。** ワークフローが時刻から作る（年.月日.時分。例 `2026.1018.616`）ので、必ず前より大きくなる。各要素の先頭の0は落としてある（Apple側の表示と、設定画面の表示をそろえるため。T-032）
-- **版（`MARKETING_VERSION`）は節目で手で上げる。毎回でなくてよい。** 同じ版の中でも、ビルド番号が大きい方が新しいものとして並ぶ
-  - Initial commit から 2026-10-13 まで `0.1.0` のままで、2026-10-14 に `0.2.0` にした
-- 上げるときは `project.yml` と `project.pbxproj`（2か所）を揃える。CIは `xcodegen generate` で作り直すので、**効くのは `project.yml`**
+- **版（`MARKETING_VERSION`）は、新しい更新版を配信するたびに末尾を1つ上げる**（2026-10-22 利用者が決定）。2.0.0 は配信済みのまま変えず、次の配信から 2.0.1 → 2.0.2 → 2.0.3
+  - 上げるのは、前の配信のあとに入った変更を、新しく TestFlight などへ配信するとき。コミットやテストのたびには上げない
+  - 同じ版のビルドが失敗してやり直すとき（書き出し・送信・Apple 側の処理の失敗）は上げない
+  - 確かめた同じビルドを App Store の審査・公開へ進めるだけなら上げない
+  - 上げるのは配信の前の PR の中で。`project.yml` と `project.pbxproj`（2か所）を揃える。CIは `xcodegen generate` で作り直すので、**効くのは `project.yml`**
+  - アプリの版の表示（設定画面の一番下）は `CFBundleShortVersionString` から読むので、配信の版と同じになる。手順5の `archive app:` の次の2行で確かめる
+  - 2.0.0 より下には戻さない（TestFlight に 2026-09-01 の事故の 1.0 が残っている。T-033）
+  - これまで: Initial commit から 2026-10-13 まで `0.1.0`、2026-10-14 に `0.2.0`、その後 `2.0.0`
```
