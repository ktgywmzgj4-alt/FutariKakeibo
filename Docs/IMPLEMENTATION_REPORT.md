# 実装・検証レポート

更新日: 2026-08-13

## 結論

空の状態から、iOS 17以降向けSwiftUIアプリのTestFlight準備版を作成した。ローカルで完結する家計簿機能、端末内レシートOCR、招待制CloudKit共有、プライバシー関連リソース、単体テスト、公開準備文書を含む。

ただし、この作業環境はLinuxでXcode/iOS SDKを利用できないため、iOSコンパイラによるビルド、シミュレータ、実機2台、CloudKit Production、Archiveは未検証である。したがって現時点は「TestFlightへ提出可能と断定できる完成版」ではなく、Macで最終検証するためのソース候補である。

## 実装した範囲

- 初期設定: 2人の呼び名、共同月予算
- ホーム: 月支出、残予算、カテゴリ集計、精算、最近の支出
- 支出: 追加、編集、検索、絞り込み、確認付き削除
- 精算: 2人で折半 / 個人を区別し、奇数円は支払者が1円多く負担
- 保存: Application Support内の保護付きJSON、CSV出力
- レシート: VisionKit撮影、Visionの端末内OCR、保存前の候補確認
- 共有: CloudKit Private/Shared Database、CKShare招待、手動/前面復帰同期
- 競合対策: 更新日時による新しい編集の優先、永続的な削除印による誤復活防止
- プライバシー: Public Database不使用、画像非保存、追跡/広告/外部解析SDKなし
- 公開準備: App Icon、Privacy Manifest、App Store素材案、収益化3案、ポリシー要件、TestFlightチェックリスト

## 修正した重要問題

| 優先度 | 問題 | 対応 |
| --- | --- | --- |
| P0 | 公開DB経由で家計情報が見える危険 | Private/Shared Databaseと非公開CKShareだけを使用 |
| P0 | 長期オフライン端末から削除済み支出が復活し得る | CloudKitのExpenseレコードへ削除印を永続化し、古い再送より優先 |
| P1 | レシート画像やOCRが外部送信される危険 | VisionKit/Visionだけで端末内処理し、画像を保存しない |
| P1 | CSV一時ファイルに家計情報が残る | ファイル保護を適用し、共有シート終了後に削除 |
| P1 | 奇数円の折半ルールと計算結果が不一致 | 各支出ごとの整数半額を精算し、1001円なら500円だけ返す |
| P1 | CloudKit取得中の個別レコードエラーを無視 | 同期失敗として扱い、不完全な一覧で上書きしない |

## この環境で実行した検証

| 検証 | 結果 |
| --- | --- |
| 必須ファイル、plist、xcprivacy、Asset JSON | 成功 |
| Xcode `project.pbxproj` 構文解析 | 成功（アプリ/テストの2ターゲット） |
| Swift構文解析 | 成功（33ファイル） |
| ドメイン受入スモークテスト | 6件成功 |
| 秘密鍵・既知の認証キー形式 | 検出なし |
| 任意通信クライアント、HTTP URL、ログ出力、解析SDK | Swiftソース内で検出なし |
| App Icon | 1024×1024、RGB、不透明 |
| 主要画面の静的デザインQA | ホーム/追加/履歴/設定の4画面で文字・配置・配色を確認 |

## Mac/実機で残るP0確認

1. Xcode 16以降でDebug/Releaseをビルドし、コンパイルエラーと警告を解消する。
2. iPhone SimulatorでXCTest全件を実行する。
3. 利用者のTeam、固有Bundle ID、同じIDのCloudKitコンテナを設定する。
4. 別Apple Accountの実機2台で招待、双方向同期、同時編集、機内モード復帰を確認する。
5. Development schemaを確認後、承認を得てProductionへデプロイする。
6. Distribution ArchiveをValidateし、プライバシーレポートと署名を確認する。
7. 実レシート20種類以上で候補精度を記録し、画像が保存/CloudKit/CSVへ残らないことを確認する。

価格、StoreKit課金、Apple Developer/App Store Connect上の登録、CloudKitコンテナ作成、Productionデプロイ、ビルド提出は行っていない。
