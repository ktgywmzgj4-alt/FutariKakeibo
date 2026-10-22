# プライバシーポリシーに必要な項目

公開URLに掲載する最終文面には、以下が必要です。運営者名と問い合わせ先は未確定のため、勝手に記入していません。
原稿は `Docs/drafts/privacy-policy.md`（D3。個人の情報は空欄のまま）。

AppleはApp Storeの商品ページに公開アクセス可能なプライバシーポリシーURLを必須としている。
参考: https://developer.apple.com/app-store/app-privacy-details/

## 必須項目

1. 運営者名または事業者名
2. 問い合わせ用メールアドレス
3. 適用対象アプリ名「ふたり家計簿」
4. 取得・処理するデータ
5. 利用目的
6. 保存場所と保護方法
7. 第三者提供・委託の有無
8. CloudKit / Appleへのデータ送信
9. 保存期間
10. 利用者による閲覧・訂正・削除方法
11. 共有相手を招待・解除した場合の扱い
12. 未成年者の利用方針
13. セキュリティ対策
14. 国外移転が発生する可能性とAppleの規約への参照
15. ポリシー変更時の通知方法と改定日

## 現在のデータ対応表（2026-10-22 にコードで確かめた。D2・T-060）

「開発者が読めるか」は2つに分けて書く（利用者の指示）: **データベースを直接見られるか**と、**招待の情報から共有に参加できるか**。

| データ | 置き場所 | 直接見られる人 | 招待の情報から参加して見られるか | 残る期間（いまのコード） |
| --- | --- | --- | --- | --- |
| 2人の呼び名・予算・支出・収入・定期支出・覚えた店（店名・種類・店の電話番号と登録番号・合計の行の書き方・人が直した品の書き方と名前・種類） | 端末の中。共有を始めたら、作った人の iCloud の Private Database（参加者は Shared Database から） | 端末の持ち主。共有中は参加者。**開発者は見られない**（CloudKit Console で見られるのは開発者自身の iCloud の分だけ） | **いまは見られる。** 公開の権限が「URLを知っている人なら参加できる」で、共有のURLが公開データベースの合言葉のレコードに入っているため（`Docs/SHARING_REVOCATION_DESIGN.md` 5章）。名指しの共有にすれば見られない | 端末: アプリを消すか「このiPhone内のデータを削除」まで。iCloud: 家計簿が消えるまで。**記録を消しても、金額・店名・メモなどの中身は削除印として iCloud に残る**（`deleteExpense` は削除の印と時刻を書くだけ） |
| レシート画像（保存がONのとき、長辺1600pxまで縮小した1枚と小さな見本） | 端末の中。共有中は作った人の iCloud（参加者も見られる） | 同上 | 同上 | 支出を消すと端末と iCloud から消す。**通信できなかったとき iCloud の画像は残り、やり直さない** |
| レシートの文字（読み取った結果） | 端末の中（保存前の画面だけ） | 端末の持ち主 | — | 保存しない |
| 合言葉のレコード（共有のURL・期限）と、CloudKit が付ける作成者のID（作った人） | CloudKit の Public Database | **開発者（CloudKit Console）。** アプリの利用者は合言葉を知っていれば1件読める | 共有のURLそのものが参加の鍵（いま） | 使われた・期限切れのものは、発行した人が共有の画面を開いたときに消す。開かなければ残る。アプリを消した人・「このiPhone内のデータを削除」をした人の発行した分は残り続ける |
| 使われた印（期限）と、作成者のID（参加した人） | CloudKit の Public Database | 開発者 | 鍵にはならない | **消していない（残り続ける）** |
| 共有の参加者（名前は iCloud が教えるときだけ） | Apple（共有の記録） | 共有の参加者どうし。開発者は見られない | — | 共有が続くあいだ |
| 端末のプッシュの登録（閉じているあいだの通知） | Apple | 開発者は受け取らない | — | Apple の扱い |
| 通知の設定・通知した支出のID・購読の時刻 | 端末の中（UserDefaults） | 端末の中だけ | — | アプリを消すまで（「このiPhone内のデータを削除」では消えない） |
| CSV | 利用者が選んだ共有先 | 利用者が選んだ相手 | — | 共有先の扱い。アプリが作る一時ファイルは共有の画面を閉じると消す |

端末の中のファイルは、iPhone のロックを最初に解除するまで読めない形で保存している（`completeUntilFirstUserAuthentication`）。
端末のバックアップを使っている人は、その中にも入る。Apple の説明（File System Programming Guide）: "files in `Documents/` and `Application Support/` are backed up by default."
このアプリはバックアップから外す指定をしていない。バックアップは Apple の仕組みで、開発者は読めない。

## App Privacy の申告（D2。項目ごとの理由）

Apple の定義: 「"Collect" refers to transmitting data off the device in a way that allows you and/or your third-party partners to access it for a period longer than what is necessary to service the transmitted request in real time.」
CloudKit について: 「If you collect data about your app from Apple frameworks or services, you should indicate what data you collect and how you use it. You are not responsible for disclosing data collected by Apple.」
「Data that is processed only on device is not "collected"」。「"Personal Information" and "Personal Data", as defined under relevant privacy laws, are considered linked to the user.」

**申告は D1（共有の方式）で2通りに分かれる。** 推奨は、公開前に名指しの共有にしたうえでの「申告する」列。

| Apple の項目 | 名指しの共有にした場合 | 理由 | いまの共有のまま出す場合 |
| --- | --- | --- | --- |
| User ID | **申告する**（App Functionality、Linked、Tracking なし） | 公開データベースの合言葉と使われた印に、CloudKit が作成者のIDを付け、開発者が読める。Apple の User ID の説明「account ID, assigned user ID ... that can be used to identify a particular user or account」に当たる | 申告する |
| Other Data Types（招待の共有URL） | **申告する**（App Functionality、Linked）。ただし合言葉で暗号にして置く対策（H1）をすれば外せる | 開発者が読める場所に、利用者の共有に結びつくURLを置いている。Apple の説明「Any other data types not mentioned」 | 申告する |
| Name・Other Financial Info・Other User Content・Photos or Videos | **申告しない** | 置き場所は利用者の iCloud（Private / Shared Database）だけで、開発者は直接見られず、招待の情報からも参加できない。Apple が扱うもので、開発者は受け取らない | **申告する側に倒す。** 開発者が招待の情報から参加すれば見られるため、「開発者がアクセスできない」と言えない |
| Device ID・Diagnostics・Usage Data・Location・Contacts など | 申告しない | 取っていない（外部のSDK・解析・広告は無い。通信は CloudKit だけ） | 申告しない |

Privacy Manifest（`PrivacyInfo.xcprivacy`）の「集めるデータ」と App Store Connect の回答は、この表で決めた列にそろえる。
**いまの Privacy Manifest は Name・Other Financial Info・Other User Content・User ID で、どちらの列とも合っていない。** D1 が決まったら直す（理由つきAPIの申告は 2026-10-22 に済ませた）。

## 削除の手順として書けること・書けないこと（D14・T-070）

| 消したい人 | 操作 | 消えるもの | 残るもの | 確かめ方 |
| --- | --- | --- | --- | --- |
| 共有していない人 | アプリを削除する | 端末の中の家計簿・レシート画像・設定 | iCloud には置いていない（共有を始めるまで iCloud に送らない） | コード（`prepareShare` で初めて送る） |
| だれでも | アプリの「このiPhone内のデータを削除」 | 端末の中の家計簿・レシート画像 | iCloud の家計簿（相手も見られる）、通知の設定、合言葉のレコード（控えが消えるので、後から片付けられなくなる） | コード（`eraseLocalData`）と画面の説明 |
| だれでも | アプリで記録を消す | 両方の画面から消える。レシート画像は iCloud から消す（通信できたとき） | **記録の中身（金額・店名・メモなど）は削除印として iCloud に残る** | コード（`deleteExpense`） |
| 作った人 | 共有をやめる | 参加者が入れなくなる | 家計簿（作った人の iCloud）、参加者の端末の写し | **画面では、ふたりより多いときだけ出る** |
| 参加した人 | 家計簿から抜ける | — | — | **アプリに操作が無い** |
| 作った人 | iPhone の設定 → iCloud → ストレージを管理 → このアプリのデータを削除 | **未確認**（作った人の iCloud の家計簿と共有が消え、相手も見られなくなる見込み） | 公開データベースの記録、相手の端末の写し（見込み） | Apple のサポートページはこの環境から読めない。テスト用アプリで確かめる（`Docs/TEST_APP_PLAN.md`） |
| 参加した人 | 同じ設定の操作 | **未確認**（家計の記録は作った人の iCloud にあるので、ほぼ何も消えない見込み） | 参加した人が登録した記録、使われた印 | 同上 |

→ **いまの代わりの手順では、要る削除ができない**（参加した人が抜けられない・作った人がふつうに共有をやめられない・消した記録の中身が残る・公開データベースの記録が残る・設定からの削除が未確認）。
公開後の対応と決めつけず、公開前の対策を提案する（`Docs/RELEASE_PLAN.md` 5-4 の M1〜M5）。**確かめていない操作を、確実な削除の手順としてポリシーに書かない。**

## 現行実装に合わせた要点

- 広告トラッキングなし
- 第三者解析SDKなし
- 位置情報・連絡先・マイクを取得しない
- レシートの文字は端末の中だけで読み取り、外部のサーバーへ送らない
- レシート画像は「レシート画像を保存」がONのときだけ、縮小した1枚を端末と共有先のiCloudに残す。支出を消すと画像も消す（通信できなかったときの iCloud の分は、上の表）
- 家計のデータはCloudKitのPrivate/Shared Database（家計簿を作った人のiCloudの中の、参加した人が読み書きできる場所）に置く。開発者は直接見られない
- CloudKitのPublic Databaseには、合言葉ごとに共有の場所と期限を置く（家計のデータは置かない）。開発者は読める。合言葉は1回だけ・1日で期限切れ
- 共有は「合言葉（共有のURL）を知っている人なら参加できる」形。合言葉は相手にだけ伝える必要がある。参加している人は共有の画面で見られる
- 相手の支出の通知は、設定でONにしたときだけ。通知の文はこの端末で作り、金額・店名を出さない
- 利用者のCSV出力は任意操作
- 端末内データ削除機能あり（iCloud の家計簿は消えない）

## 公開前に必要な追加判断

- 運営者名の書き方と、問い合わせ用の専用メールアドレス（D3。本人の情報待ち）
- 共有の方式（D1）。App Privacy の申告とポリシーの言い方がこれで決まる
- 削除の対策（D14。M1〜M5）と、設定からの削除をテスト用アプリで確かめること
- 公開用WebページのURL（掲載先の推奨は `Docs/drafts/README.md`）
- 削除の依頼をメールでも受け付けるか（受け付けるなら、公開データベースの記録を開発者が探して消す手順が要る）
