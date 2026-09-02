# CloudKit Production の反映手順（人間の作業）

**この作業はAIにはできません。** CloudKit Console はブラウザの手作業でしか操作できず、
Appleのアカウントにログインする必要があります。

**先に読んでください: `Docs/safety.md`**
CloudKitのProductionに入れた項目は、**二度と消せません。名前も変えられません。**
打ち間違えたまま反映すると、その名前が永久に残ります。

## なぜ必要か

CloudKitには「Development（開発用）」と「Production（本番用）」の2つの環境があります。
Xcodeから動かすアプリはDevelopmentを、**TestFlightで配ったアプリはProductionを**見ます。

Developmentは、アプリがデータを保存すると項目を自動で作ってくれます。
Productionは作ってくれません。**人間が手で反映する必要があります。**

これをやるまで、TestFlightのアプリでは共有も同期も動きません。

## 手順

1. https://icloud.developer.apple.com/dashboard/ を開く
2. Apple Developer アカウントでログイン
3. コンテナ **`iCloud.jp.aikawa.futarikakeibo`** を選ぶ
4. 左上の環境が **Development** になっていることを確認する
5. 左メニューの **Schema → Record Types** を開き、下の4つが揃っているか確認する
6. 揃っていたら **Deploy Schema Changes...** を押す
7. 差分の一覧が出るので、**Record Type の名前と項目名を1つずつ読む**（ここが最後の確認です）
8. **Deploy to Production** を押す

## Development に4つ揃っていない場合

アプリを一度も動かしていないと、Developmentにも項目がありません。
その場合は、**実機かシミュレータでアプリを開き、支出と収入を1件ずつ登録**してください。
それでCloudKitが項目を自動で作ります。作られたら手順5に戻ります。

## 反映されるはずのもの

**2026-09-03 追記**: `Household` に `merchantMemosData` が増えました（覚えた店の一覧）。
まだProductionへ反映していないので、**この項目も一緒に入ります**。反映前に気づけてよかった項目です。

コード（`FutariKakeibo/Services/CloudKitSyncService.swift`）が使っている項目です。

| Record Type | 項目 |
| --- | --- |
| `Household` | id, name, monthlyBudget, ownerMemberID, membersData, categoryBudgetsData, recurringExpensesData, **merchantMemosData**, createdAt, updatedAt |
| `Expense` | id, isDeleted, title, amount, date, category, paidByMemberID, splitMethod, note, recurringID, createdAt, updatedAt |
| `Income` | id, isDeleted, title, amount, date, source, receivedByMemberID, note, createdAt, updatedAt |
| `ShareInvite` | shareURL, expiresAt |

`ShareInvite` だけは **Public Database** に置きます。
他の3つは Private Database の中の、招待した相手だけが読める場所（共有ゾーン）です。

## 終わったら

`tasks.json` の `T-002` の `evidence` に、
**Production環境のRecord Types一覧が写ったスクリーンショット**の場所を書いてください。
それが済むまで `T-003`（2台での共有確認）は始められません。
