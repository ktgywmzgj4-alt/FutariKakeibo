# WindowsだけでTestFlightに配信する手順

Macを使わずに、自分のiPhoneへ実機インストールするまでの全工程です。
証明書の作成はGit Bash同梱のOpenSSLで行い、ビルドはGitHub Actionsのmacosランナーが行います。

所要時間の目安: 設定に1〜2時間、ビルドとApple側の処理に30〜60分。

## 前提

- Apple Developer Program に加入していること（年額。未加入ならまず加入）
- iOS 17以降のiPhone
- このリポジトリへの管理者権限（Secretsを登録するため）

プロジェクトに設定済みの値:

| 項目 | 値 |
| --- | --- |
| Team ID | `79XN3292J9` |
| Bundle ID | `jp.aikawa.futarikakeibo` |
| iCloudコンテナ | `iCloud.jp.aikawa.futarikakeibo` |
| プロファイル名 | `FutariKakeibo App Store` |

プロファイル名はワークフローの `PROFILE_NAME` と一致していないと署名に失敗します。

## 1. App IDとiCloudコンテナを登録する

Apple Developerのアカウントページで行います。

1. Certificates, Identifiers & Profiles → Identifiers → 「+」
2. App IDs → App を選び、Explicit で `jp.aikawa.futarikakeibo` を登録
3. Capabilities で **iCloud** にチェック
4. Identifiers → iCloud Containers → 「+」で `iCloud.jp.aikawa.futarikakeibo` を作成
5. 手順2で作ったApp IDを開き、iCloudの「Edit」から作成したコンテナを割り当てる

コンテナを割り当てないと、Entitlementsと一致せず署名段階で失敗します。

## 2. 配布証明書をWindowsで作る

MacのKeychain Accessの代わりにOpenSSLでCSRを作ります。Git Bashで実行してください。

```bash
mkdir -p ~/ios-signing && cd ~/ios-signing
openssl genrsa -out distribution.key 2048
openssl req -new -key distribution.key -out distribution.certSigningRequest \
  -subj "/emailAddress=あなたのAppleID/CN=FutariKakeibo Distribution/C=JP"
```

1. Apple Developer → Certificates → 「+」→ **Apple Distribution**
2. `distribution.certSigningRequest` をアップロード
3. `distribution.cer` をダウンロードし、`~/ios-signing` に置く

証明書と秘密鍵をまとめて `.p12` にします。パスワードを聞かれるので、自分で決めた値を入力してください（あとでSecretsに登録します）。

```bash
cd ~/ios-signing
openssl x509 -inform DER -in distribution.cer -out distribution.pem
openssl pkcs12 -export -inkey distribution.key -in distribution.pem -out distribution.p12
```

`distribution.key` は再発行できません。証明書を作り直すまで消さないでください。

## 3. プロビジョニングプロファイルを作る

1. Apple Developer → Profiles → 「+」
2. Distribution の **App Store Connect** を選択
3. App IDに `jp.aikawa.futarikakeibo` を選択
4. 証明書に手順2で作ったものを選択
5. 名前を **`FutariKakeibo App Store`** と入力（この文字列でないとビルドが失敗します）
6. ダウンロードして `~/ios-signing` に置く

## 4. App Store Connectにアプリを登録する

1. App Store Connect → アプリ → 「+」→ 新規App
2. プラットフォーム: iOS
3. 名前: `ふたり家計簿`（App Store全体で重複不可。取られていたら別名に）
4. 主要言語: 日本語
5. バンドルID: `jp.aikawa.futarikakeibo`
6. SKU: `futarikakeibo-001` など任意の管理用文字列

この時点では審査に出しません。TestFlightで自分が使うだけなら公開情報の入力は不要です。

## 5. App Store Connect APIキーを作る

1. App Store Connect → ユーザとアクセス → 「Integrations」→ App Store Connect API
2. 「Team Keys」で「+」、名前は `GitHub Actions`、アクセス権は **App Manager**
3. `.p8` ファイルをダウンロード（**1回しかダウンロードできません**）
4. 一覧に表示される **Key ID** と、ページ上部の **Issuer ID** を控える

## 6. GitHub Secretsに登録する

まずBase64にします。

```bash
cd ~/ios-signing
base64 -w0 distribution.p12 > distribution.p12.b64
base64 -w0 *.mobileprovision > profile.b64
base64 -w0 AuthKey_*.p8 > authkey.b64
```

GitHubのリポジトリ → Settings → Secrets and variables → Actions で6つ登録します。

| Secret名 | 中身 |
| --- | --- |
| `APPLE_DISTRIBUTION_CERTIFICATE_BASE64` | `distribution.p12.b64` の中身 |
| `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD` | 手順2で決めたパスワード |
| `APPLE_PROVISIONING_PROFILE_BASE64` | `profile.b64` の中身 |
| `APP_STORE_CONNECT_API_KEY_ID` | 手順5のKey ID |
| `APP_STORE_CONNECT_API_ISSUER_ID` | 手順5のIssuer ID |
| `APP_STORE_CONNECT_API_PRIVATE_KEY_BASE64` | `authkey.b64` の中身 |

ブラウザに長い文字列を貼るのが面倒なら、`gh` から登録できます。

```bash
gh secret set APPLE_DISTRIBUTION_CERTIFICATE_BASE64 < distribution.p12.b64
gh secret set APPLE_PROVISIONING_PROFILE_BASE64 < profile.b64
gh secret set APP_STORE_CONNECT_API_PRIVATE_KEY_BASE64 < authkey.b64
gh secret set APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD
gh secret set APP_STORE_CONNECT_API_KEY_ID
gh secret set APP_STORE_CONNECT_API_ISSUER_ID
```

登録後は `~/ios-signing` をバックアップし、`.b64` ファイルは消して構いません。

## 7. ビルドしてアップロードする

1. GitHub → Actions → 「iOS build and tests」
2. 「Run workflow」で `main` を選んで実行

`test`（ビルドとXCTest）が通ってから `testflight`（署名・IPA書き出し・アップロード）が動きます。合計15〜25分。

ビルド番号はワークフロー実行番号を使うので、2回目以降も重複しません。

## 8. iPhoneに入れる

1. App Store Connect → TestFlight でビルドの処理完了を待つ（10〜30分、完了時にメールが届く）
2. 「内部テスト」でグループを作り、自分を追加
3. iPhoneにApp Storeから **TestFlight** アプリを入れ、同じApple IDでサインイン
4. 招待が届いたらインストール

内部テスターはBeta App Reviewが不要なので、そのまま入ります。
パートナーに渡す場合は外部テスターとして招待し、初回だけBeta App Reviewを通します。

## 9. iCloud共有を使う場合（あとから）

手順8までで、このiPhone内に保存する機能はすべて使えます。2人で共有する場合だけ追加作業が必要です。

Macがないと開発ビルドでスキーマを自動生成できないため、CloudKit Consoleで手作業で作ります。

`Household` レコード型:

| フィールド | 型 |
| --- | --- |
| `id` | String |
| `name` | String |
| `monthlyBudget` | Int64 |
| `ownerMemberID` | String |
| `membersData` | Bytes |
| `categoryBudgetsData` | Bytes |
| `recurringExpensesData` | Bytes |
| `createdAt` | Date/Time |
| `updatedAt` | Date/Time |

`Expense` レコード型:

| フィールド | 型 |
| --- | --- |
| `id` | String |
| `isDeleted` | Int64 |
| `title` | String |
| `amount` | Int64 |
| `date` | Date/Time |
| `category` | String |
| `paidByMemberID` | String |
| `splitMethod` | String |
| `note` | String |
| `recurringID` | String |
| `createdAt` | Date/Time |
| `updatedAt` | Date/Time |

`Expense` はゾーン内を検索するため、Indexesで `recordName` を **Queryable** にしてください。これがないと同期時に「not marked queryable」で失敗します。

作成したらDevelopmentからProductionへデプロイします。TestFlightのビルドはProduction環境を使うため、デプロイしないと共有が動きません。

## つまずきやすいところ

| 症状 | 原因 |
| --- | --- |
| `No profiles for 'jp.aikawa.futarikakeibo' were found` | App IDが未登録、またはプロファイル名が `FutariKakeibo App Store` と違う |
| 署名時にentitlementsの不一致 | App IDにiCloud capabilityを付けていない、コンテナ未割り当て |
| `security import` が失敗する | `.p12` の作成に失敗している。`openssl pkcs12 -export` を `-legacy` 付きで作り直す |
| アップロードが `already exists` で失敗 | 同じビルド番号が既にある。ワークフローを再実行すれば番号が変わる |
| TestFlightに「輸出コンプライアンス」の確認が出る | Info.plistの `ITSAppUsesNonExemptEncryption` で回答済みのため通常は出ない |
