# TestFlight公開までのチェックリスト

価格設定・課金・外部登録・提出操作は実行していません。

## A. ソースとXcode

- [x] SwiftUIアプリ本体
- [x] 主要4画面
- [x] ローカル保存
- [x] CloudKit共有コード
- [x] 端末内OCR
- [x] Privacy Manifest
- [x] 単体テスト3ファイル
- [x] App Icon 1024px
- [x] Xcodeプロジェクトと共有Scheme
- [ ] Macの現行Xcodeでプロジェクトを開く
- [ ] Debugビルドを成功させる
- [ ] XCTestを全件成功させる
- [ ] Release / Generic iOS DeviceでArchiveを成功させる
- [ ] Analyzeで新規警告を確認する

## B. Apple Developer設定（利用者の承認・操作が必要）

- [ ] Apple Developer Programの登録状態を確認
- [ ] 一意なBundle IDを決定
- [ ] `project.pbxproj` / `project.yml` / EntitlementsのIDを同じ値へ変更
- [ ] iCloud CapabilityとCloudKitコンテナを作成・紐付け
- [ ] Development環境でRecord Type `Household` / `Expense` / CKShareを生成
- [ ] CloudKit Dashboardでschemaを確認
- [ ] Development schemaをProductionへDeploy
- [ ] 自動署名でDevelopmentとDistributionのプロファイルを確認

重要: TestFlightはCloudKit Production環境を使うため、schema未デプロイのままでは共有が動かない。

## C. 実機2台テスト

- [ ] それぞれ別の個人用Apple AccountでiCloudにサインイン
- [ ] Aで家計を作成し、Bだけを招待
- [ ] Bが招待を受け、同じ支出一覧を確認
- [ ] A→B / B→Aの追加・編集・削除
- [ ] 同じ支出をほぼ同時に編集
- [ ] 機内モードで追加し、復帰後に同期
- [ ] 機内モードで削除し、復帰後に再出現しない
- [ ] アプリ強制終了・端末再起動後もデータが残る
- [ ] カメラ拒否時にクラッシュしない
- [ ] レシート20種類以上で金額を確認
- [ ] 大きな文字、VoiceOver、ダークモード固定時の視認性
- [ ] CSVに期待する項目だけが入る
- [ ] レシート画像が端末ファイル・CloudKit・CSVに残らない

## D. App Store Connect準備（まだ実行しない）

- [ ] App Store Connectにアプリレコードを追加
- [ ] アプリ名、Bundle ID、SKUを設定
- [ ] Beta App Description
- [ ] What to Test
- [ ] Feedback Email
- [ ] Beta App Review連絡先
- [ ] プライバシーポリシー公開URL
- [ ] App Privacy回答
- [ ] 輸出コンプライアンス回答
- [ ] 年齢区分
- [ ] スクリーンショット（架空データ）
- [ ] App Store説明文・キーワード・カテゴリ

Appleの案内では、TestFlightにはベータ説明、テスト内容、フィードバック先が必要。ビルドは最大90日テストでき、外部テスターの初回ビルドはBeta App Review対象となる。
参考: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview

## E. 本人＋パートナーの配布方法

推奨構成:

- 本人：App Store Connectの権限を持つ内部テスター
- パートナー：メール招待の外部テスター

パートナーを内部テスターにするためだけにApp Store Connectの開発権限を与えない。外部テスターは初回Beta App Reviewが必要になりうるが、アカウント権限を最小化できる。

## F. アップロード（明示承認後のみ）

- [ ] Version `0.1.0` / Build `1`を確認
- [ ] Product > Archive
- [ ] OrganizerでValidate App
- [ ] Distribute App > App Store Connect > Upload
- [ ] Processing完了メールを待つ
- [ ] Missing Complianceがあれば輸出回答
- [ ] 内部テストを開始
- [ ] 外部グループにパートナーを追加し、Beta App Reviewへ送る
- [ ] 招待メールからインストール

Appleは、アプリレコード作成後にXcode等からビルドをアップロードでき、Bundle ID・Version・Build Stringでビルドを関連付けるとしている。
参考: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
