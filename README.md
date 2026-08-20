# ふたり家計簿

カップル2人で使う、iPhone向け共有家計簿アプリのMVPです。

## MVPでできること

- 2人分の名前と月予算を設定
- 支出の追加・編集・削除・検索
- 支払った人と「2人で折半 / 個人の支出」を記録
- 月ごとの予算進捗・カテゴリ集計・精算額を表示
- レシートを撮影し、端末内だけで店名・合計・日付・カテゴリを候補入力
- JSONによるオフライン保存（ファイル保護付き）
- CloudKitのPrivate/Shared Databaseを使った招待制共有
- CSV書き出しと全データ削除

レシート画像そのものは保存・送信しません。OCR結果も保存前に必ず利用者が確認・修正します。

## 開発環境

- Xcode 16以降を推奨
- iOS 17.0以降
- Swift 5 / SwiftUI
- Apple Developer Program（実機・TestFlight・CloudKit利用時）

## 最初に行う設定

1. `FutariKakeibo.xcodeproj` をXcodeで開く（再生成する場合は `xcodegen generate`）。
2. Target > Signing & Capabilities で自分のTeamを選択する。
3. Apple Developerに登録済みの設定値を確認する。
   - Bundle ID: `jp.aikawa.futarikakeibo`
   - iCloud Container: `iCloud.jp.aikawa.futarikakeibo`
   - Team ID: `79XN3292J9`
4. iCloud（CloudKit）が有効になっていることを確認する。
5. まず実機1台でローカル機能を確認し、その後CloudKit共有を確認する。

Bundle IDとiCloud ContainerはApple Developerへ登録済みです。価格設定、課金、証明書・プロビジョニングプロファイルの作成、TestFlight提出はまだ行っていません。

## プロジェクトの再生成

`project.yml` はXcodeGen用です。

```sh
brew install xcodegen
xcodegen generate
```

## 検査

```sh
./scripts/validate_project.sh
python3 scripts/test_domain_logic.py
```

XcodeがあるMacでは以下も実行してください。

```sh
xcodebuild -project FutariKakeibo.xcodeproj \
  -scheme FutariKakeibo \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

詳細は `Docs/` を参照してください。
