# ふたり家計簿

カップル2人で使う、iPhone向け共有家計簿アプリのMVPです。

## MVPでできること

- 2人分の名前と月予算を設定
- 支出の追加・編集・削除・検索
- 支払った人と「2人で折半 / 個人の支出」を記録
- 月ごとの予算進捗・カテゴリ集計・精算額を表示
- 家賃やサブスクを定期支出として登録し、指定した日に自動で計上
- カテゴリごとの月予算と、使いすぎたときの警告
- 月次レポート（6か月の推移、カテゴリ内訳、2人の負担割合、前月比）
- レシートをカメラで撮る、または保存済みの写真から選び、端末内だけで店名・日付・合計・明細を読み取って候補入力
- 読み取ったレシート画像を縮小して保管し、支出の詳細から見返す（保存はONとOFFを選べます）
- JSONによるオフライン保存（ファイル保護付き）
- CloudKitのPrivate/Shared Databaseを使った招待制共有
- CSV書き出しと全データ削除

レシートの読み取り（OCR）は端末内だけで行い、外部のサーバーへは送りません。OCR結果は保存前に必ず利用者が確認・修正します。

レシート画像は、「レシート画像を保存」をONにしたときだけ残ります。残すのは長辺1600pxまで縮小・圧縮した1枚（1枚あたり数百KB程度）で、
撮った原寸の画像は読み取りが終わった時点で捨てます。iCloud共有を有効にしている場合、保存した画像は招待した相手も見られます。
支出を削除すると、その支出のレシート画像も端末とiCloudの両方から削除されます。

## 開発環境

- Xcode 16以降を推奨
- iOS 17.0以降
- Swift 5 / SwiftUI
- Apple Developer Program（実機・TestFlight・CloudKit利用時）

## 最初に行う設定

1. `FutariKakeibo.xcodeproj` をXcodeで開く（再生成する場合は `xcodegen generate`）。
2. Target > Signing & Capabilities で自分のTeamを選択する。
3. Bundle Identifierと `FutariKakeibo.entitlements` のiCloudコンテナIDを、自分の一意な値に変更する。
4. iCloud（CloudKit）が有効になっていることを確認する。
5. まず実機1台でローカル機能を確認し、その後CloudKit共有を確認する。

Apple Developer上でのコンテナ作成、価格設定、課金、TestFlight提出はこのソースには含まれません。

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
