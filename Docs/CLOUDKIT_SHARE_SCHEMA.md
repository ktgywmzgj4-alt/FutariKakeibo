# 合言葉が発行できない原因と、その直し方

実機で「合言葉を発行できませんでした」が出続ける原因は、アプリのコードではなく
**CloudKitのスキーマ**です。この文書はその直し方の全工程です。

所要時間の目安: Apple Developerでの設定に30〜60分、あとはビルド待ちが10分ほど。

## 何が起きているか

実機のログで掴んだエラーはこれです。

```
startSharingWithCode → prepareShare.createShare → modifyRecords
CKError 12 / CKInternalError 2006   （invalidArguments）
CKError 22 / CKInternalError 2024   （batchRequestFailed・巻き添え）
```

`CKShare` を保存するには、コンテナのスキーマに **`cloudkit.share`** という型が
要ります。いまこれが Development にも Production にもありません。

**この型は手では作れません。** CloudKit Console の画面から追加することもできません。
**Development環境で実際に共有を1回保存したときだけ**、CloudKitが自動で足します。
そのあと Deploy Schema Changes で Production へ運びます。

ここが行き止まりになっていた理由: **TestFlightのビルドは必ず Production につながります。**
だからTestFlightで何度試しても、この型は永遠に増えません。

Appleのサポートも同じ原因で同じエラーを説明しています。
https://developer.apple.com/forums/thread/841618

## 何が要るか

**GitHub Secrets に新しく足すものはありません。** 端末の登録も、Ad Hoc プロファイルの
作成も、TestFlight配信で使っているのと同じ App Store Connect のAPIキーでできます
（`scripts/asc_adhoc_profile.rb` がやります）。証明書も配信用を使い回します。

必要なのは **iPhoneのUDID** だけです。Apple Developer のポータルを開く必要はありません。

## 1. iPhoneのUDIDを調べる

Windowsでできます。

1. iPhoneをUSBでつなぐ
2. **Apple Devices** アプリ（Windows 11用）を開く。無ければ iTunes でも同じ
3. サイドバーでiPhoneを選び、端末名のすぐ下の情報の部分を**クリック**する
4. シリアル番号・UDID などが順に切り替わる。**「UDID」と出ているときの値**を控える

シリアル番号・IMEI とは別物です。UDIDは `00008110-001234510EEB801E` のような形。

2台で共有を試すなら、**2台ぶん**控えてください。

## 2. Development環境のビルドを作る

GitHub の **Actions → 「iOS dev-environment build」→ Run workflow**。

- ブランチ: `main`
- **UDID の欄に、控えたUDIDをカンマ区切りで入れる**（登録済みなら空でよい）

ワークフローがこの順で動きます。

1. UDIDをApp Store Connectに登録する（すでにあれば飛ばす）
2. `FutariKakeibo Ad Hoc` のプロファイルを**作り直す**（プロファイルは後から端末を
   足せないので、毎回消して作る。だから端末が増えても同じ手順で済む）
3. `iCloudContainerEnvironment` を Development にしてIPAを書き出す
4. **書き出したIPAの署名を読んで、本当に Development か確かめる**

App Store Connect には**何も送りません**。最後に「iCloudの環境: Development」と出れば
成功です。Productionになっていたらその場で止まるので、入れてから気づくことはありません。

完了したら、実行ページの下の **Artifacts** から zip をダウンロードします。

## 3. iPhoneに入れる

Ad HocのIPAは、HTTPS越しにリンクを開くとiPhoneに直接入ります（OTAインストール）。
Windowsからでもできます。Diawi や InstallOnAir のような受け渡しサービスにzipから
取り出したIPAを上げ、出てきたリンクをiPhoneのSafariで開く形が一番早いです。

**注意**: この方法だと、署名済みのアプリ本体が外部のサービスを一度通ります。
秘密情報は入っていませんが、外に出す判断はご自身でしてください。自分でHTTPSの
置き場を用意して `manifest.plist` を書く方法でも同じことができます。

入れると、TestFlight版と**同じアプリとして上書き**されます（バンドルIDが同じため）。
手元の家計簿データは消えません。

## 4. 共有を1回つくる

Development版のアプリで、設定 → ふたりで共有 → **合言葉を発行する**。

ここで成功するはずです。Development環境は、無い型を自動で作ってくれるからです。
**8文字の合言葉が出たら、`cloudkit.share` が生まれています。**

2台ぶん登録してあるなら、ここでもう1台から参加まで試してください。
**Productionに触らずに、共有機能の全体を通しで確かめられる**ので、やっておく価値があります。

## 5. 型を確かめて、Productionへ運ぶ

1. CloudKit Console → コンテナ `iCloud.jp.aikawa.futarikakeibo`
2. **Development** → Record Types に **`cloudkit.share`** が増えていることを確認
3. **Deploy Schema Changes...** → 中身を読んでから **Confirm Deployment**
4. **Production** → Record Types にも `cloudkit.share` が来ていることを確認

もし差分なしと言われて進めない場合は、Appleのサポートが Reset Environments を
案内しています。ただし**これはDevelopmentのスキーマを上書きする操作**なので、
実行する前に一度相談してください。

## 6. TestFlightの版で確かめ直す

TestFlightから元のビルドを入れ直して、もう一度「合言葉を発行する」。
ここで8文字が出て、別のApple IDの端末から参加できたら完了です。

これが `tasks.json` の **T-016** の合格条件です。

---

## 知っておいたほうがいいこと

**手元の家計簿データは消えません。** Development版を入れても上書きインストールなので、
端末内の `snapshot.json` はそのまま残ります。アプリを**削除**すると消えるので、
削除はしないでください。念のため、始める前に設定からCSVで書き出しておくと安心です
（ただし**このアプリにCSVの取り込み機能はありません**。読む用の控えです）。

**Development版で合言葉を発行すると、いまの家計簿がDevelopment環境にも上がります。**
`prepareShare` は支出と収入を全部アップロードするためです。同じiCloudアカウントの
中なので他人には見えませんが、気になるならCloudKit Consoleの
Reset Development Environment であとから消せます。

**共有の置き場所（`cloudLocation`）は環境をまたいでも壊れません。** ゾーン名は
家計簿のIDから決まっていて、DevelopmentとProductionで同じ名前になります。
TestFlight版に戻せば、Production側のゾーンをそのまま見つけます。

**TestFlightはDevelopmentにつなげません。** 配信の仕組み上こうなっているので、
この回り道が要ります。Appleのサポートの回答は
https://developer.apple.com/forums/thread/842909 にあります。
