# 構成・実装状況・リスク整理

更新日: 2026-08-13

## 使用技術

| 領域 | 採用技術 | 理由 |
| --- | --- | --- |
| UI | SwiftUI / iOS 17以降 | iPhoneに最適化し、外部UIライブラリを持たない |
| ローカル保存 | Codable + JSON / Application Support | 小規模MVPとして監査しやすく、オフラインで動く |
| ファイル保護 | Complete until first user authentication | 端末ロックと連動して家計データを保護する |
| 2人共有 | CloudKit Private/Shared Database + CKShare | 公開DBを使わず、招待参加者だけに共有する |
| レシート | VisionKit + Vision | 画像を外部送信せず、端末内でOCRする |
| テスト | XCTest + Linux受入スモークテスト | 金額・精算・保存・OCR抽出の回帰を防ぐ |

Appleは、CloudKitのPrivate Database内のレコードを他のiCloud利用者と共有できる仕組みを提供している。
参考: https://developer.apple.com/documentation/cloudkit/sharing-cloudkit-data-with-other-icloud-users

## 実装済み機能

- 初期設定（2人の呼び名・共同月予算）
- ホーム（月支出、残予算、カテゴリ内訳、精算額、最近の支出）
- 支出の追加・編集・検索・カテゴリ絞り込み・確認付き削除
- 支払者と「2人で折半 / 個人」の記録
- 月移動と月単位集計
- レシート撮影・日本語/英語OCR・店名/金額/日付/カテゴリ候補
- OCR候補の保存前確認と修正
- ローカル保存・CSV書き出し・端末内データ削除
- CloudKit共有招待、共有参加、前面復帰/手動同期
- オフライン削除の保留・再送とCloudKit上の永続的な削除印
- 更新日時を使った支出競合の新しい方優先
- Privacy Manifest、カメラ権限文言、秘密情報除外設定

## 意図的に未実施

- Apple Developer上のBundle ID / CloudKitコンテナ作成
- CloudKit Development schemaのProductionへのデプロイ
- 価格設定、StoreKit、課金画面
- App Store Connectのアプリ登録、ビルドアップロード、TestFlight提出
- 広告、外部解析SDK、外部AI/OCR API
- レシート画像の保存または共有

## データの流れ

1. 手入力またはレシート撮影で支出候補を作る。
2. レシート画像はVisionで端末内処理し、画面を閉じた後は保持しない。
3. 利用者が候補を確認・修正して保存する。
4. 共有前はApplication Support内の保護付きJSONだけに保存する。
5. 共有後はCloudKit Private Databaseの所有者データを、CKShare参加者のShared Databaseへ共有する。
6. CSV出力は利用者がボタンを押した場合だけ保護付き一時ファイルとして作り、共有シートを閉じた後に削除する。

## 主要リスクと現在の対策

| 優先度 | リスク | 現在の対策 | 残る確認 |
| --- | --- | --- | --- |
| P0 | 家計データが第三者に公開される | Public Database不使用、CKShareの公開権限なし | 実機2アカウントで参加者以外が開けないことを確認 |
| P0 | CloudKit設定不足でTestFlight版だけ同期不能 | Entitlementsと招待処理を実装 | Production schemaデプロイと配布ビルドでの確認 |
| P0 | コンパイル/API互換性 | Swift全ファイルの構文解析、Xcodeプロジェクト解析 | Macの現行Xcodeで実ビルドが必須 |
| P1 | オフライン編集の上書き・削除済み支出の復活 | `updatedAt`で新しい支出を優先し、CloudKit上の削除印を古い端末からの再送より優先 | 2台同時編集・長期オフライン復帰テスト |
| P1 | OCRの誤読による金額ミス | 候補扱い、保存ボタン前に編集可能、原文を表示 | 実レシート20種類以上で確認 |
| P1 | 端末紛失時のローカル漏えい | iOSファイル保護 | 実機バックアップ/復元時の挙動確認 |
| P1 | CSVに個人情報が含まれる | 明示操作時だけ保護付き一時ファイルを作り、共有シート終了後に削除 | 共有先を利用者が確認する説明を追加検討 |
| P2 | iCloud容量・一時障害 | ローカル先行保存、手動再同期 | 長期オフライン後の同期テスト |
| P2 | 削除印がCloudKitに蓄積する | 誤復活防止を優先し、初版では保持 | 運用データを見て安全な圧縮・期限方式を設計 |
| P2 | 共同家計名/メンバー名の同時更新 | Householdにも更新日時を保持 | 同時変更時のUI通知は将来対応 |

## TestFlight前の技術的な完了条件

- Mac上のXcodeでDebug/Releaseの両方が警告なしでビルドできる
- XCTest 3ファイルが成功する
- iCloudアカウントAが家計を作成し、Bだけを招待できる
- Bの追加・編集・削除がAに反映し、逆方向も反映する
- 機内モード中の追加/削除が復帰後に整合する
- レシート画像がファイルシステム・CloudKit・CSVのいずれにも残らない
- Production CloudKit schemaをデプロイした配布ビルドで同期できる
