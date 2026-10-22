# 共有をやめたら入れない・古いURLでは入れない形にする設計（D1・T-059。2026-10-22）

利用者の条件（D1、2026-10-22）:

1. 共有をやめると、以前の参加者のアクセスを止められる
2. 共有し直しても、古いURLを知っているだけでは再参加できない
3. 既存の家計データと未同期のデータを失わない

**この文書は設計と検証の準備まで。** 本番の共有の権限の変更・既存の利用者の移行・CloudKit Production の変更はしていない
（利用者の回答は、それらを承認するものではない）。前の計画は `Docs/SHARING_MIGRATION_PLAN.md`（T-048）。

根拠の書き方: 「資料」は developer.apple.com の原文（英語のまま引用）、「コード」は main のファイル、「未確認」は資料にも実機の記録にも無いもの。

---

## 1. 結論

1. **いまの作りは、条件2を満たさない。** 共有し直しても共有のURLは同じで、公開の権限が「URLを知っている人なら参加できる」なので、古いURLを控えている人はまた入れる（2章）
2. 条件2を満たす方法は、資料で確かめた範囲では **「名指しの共有」（公開の権限を使わない共有）だけ**。共有し直すたびにURLを変える方法（家計簿を作り直す・写す）は、データを動かすので採らない（3章）
3. 条件1は、仕組みはあるが、**画面では「ふたりより多く参加しているとき」しか共有をやめられない**。参加した側が自分で抜ける操作も無い（2章）。公開前の対策が要る（`Docs/RELEASE_PLAN.md` 5-4 の M1・M2）
4. **推奨: 公開の前に、新しく作る共有を名指しの形にする。** 公開後に変えると、すべての利用者のパートナーが一度外れて入り直す必要がある。公開前なら、入り直しが要るのは利用者とパートナーの家計簿だけ（4章）
5. 名指しにする方法は3つあり、**どれも実機で確かめていない**。本番と分けたテスト用アプリ（`Docs/TEST_APP_PLAN.md`）で確かめてから選ぶ（6章）
6. 名指しにすると、「開発者は家計のデータを読めない」が、招待の情報から参加する道についても言えるようになる（5章、D2）

## 2. いまの作りで3つの条件を満たすか

| 条件 | いま | 根拠 |
| --- | --- | --- |
| 1 共有をやめると以前の参加者が入れなくなる | **仕組みはある。** ただし画面のボタンは、ふたりより多く参加していて、作った人の端末のときだけ出る。参加した側が抜ける操作は無い | コード: `CloudKitSyncService.stopSharing` は共有（`CKShare`）を消す。`SharingView.membersCard` は `strangers > 0` のときだけボタンを出す。資料（CKShare.Participant）: "The records remain accessible for as long as the participant's status is accepted." |
| 2 共有し直しても古いURLだけでは入れない | **満たさない** | 資料（CKShare.url）: "This URL is stable and persists across shares and reshares of the same root record."／（CKShare.publicPermission）: "Setting this property's value to be more permissive than `none` allows any user with the share's URL to join." コード: 家計簿のレコードを根にした `CKShare(rootRecord:)`、公開の権限は `.readWrite`（`sharePublicPermission`） |
| 3 データを失わない | 共有をやめても、作った人の家計のデータは消えない（共有を消すだけ）。外れていた参加者の手元の記録は、同じ家計簿に入り直すと突き合わせて残す。**自動テストあり、実機は未確認** | コード: `stopSharing`、`AppStore.snapshotAfterJoining`・`isSameHousehold`。テスト: `RejoinSnapshotTests`（この PR で「相手が消した記録は入り直しても戻らない」を足した）、`SyncMergeTests` |

条件1の補足:

- 以前の参加者の**端末の中に残った写し**（共有をやめる前に同期した分）は、こちらから消せない。どの方法でも同じ
- 別れたときなど、ふつうに共有をやめたい人が、いまはアプリの中でやめられない

## 3. 条件2を満たす方法の比べ

| 案 | 中身 | 条件2 | データ | 判断 |
| --- | --- | --- | --- | --- |
| **A 名指しの共有**（公開の権限を `none`） | 作った人が加えた人しか入れない | 満たす。資料（CKFetchShareParticipantsOperation）: "A participant can't accept a private share unless the owner adds them first." 資料（allowsAccessRequests、iOS 26）: 既定の NO なら "the server prevents uninvited users from requesting access and does not indicate whether the share exists." | 動かさない | **採る**（加え方は下の A1〜A3） |
| B 共有し直すときにURLを変える | URLは根のレコードに結びつくので、家計簿の根を作り直すか、別の置き場所へ写す | 満たしうる | 全部の記録とレシート画像の付け替えか写しが要り、途中で失敗すると家計簿が割れる | 採らない（T-048 でも退けた） |
| C 公開の共有のまま、アプリが許した人にだけ家計簿を見せる | 画面だけで止める | **満たさない**。CloudKit の上では参加できている。このコンテナを読むアプリを作れる人（開発者）なら読める | — | 採らない |

A で参加者を加える方法（どれも実機では未確認）:

| | A1 一度きりのURL | A2 ユーザーレコードIDで名指し | A3 Apple の共有の画面 |
| --- | --- | --- | --- |
| 招き方 | いまの合言葉のまま。合言葉で引く中身が「一度きりのURL」に変わる | 合言葉 → 相手が参加を申し込む（いまの「使われた印」に相手のIDが付く）→ 作った人の端末が相手を加える（T-048 の案A） | 合言葉をやめ、相手の電話番号かメールで、メッセージ・メールから招く |
| 作る側のOS（資料の表示） | 参加者を作る `oneTimeURLParticipant()` は iOS 18 から。URLを取り出す Swift の `oneTimeURL(for:)` は **iOS 26 から** | `LookupInfo(userRecordID:)`・`CKFetchShareParticipantsOperation` は iOS 10 から | `UICloudSharingController` は iOS 10 から |
| 参加する側のOS | 資料に無い（未確認） | iOS 17 で使える見込み（未確認） | iOS 17 で使える |
| いちばんの未確認 | iOS 18〜25 で一度きりのURLを取り出せるか（Objective-C の `oneTimeURLForParticipantID:` は一覧にあるが、対応OSの表示が無い） | **発見の許可を出していない人を、ユーザーレコードIDで参加者にできるか**（資料: "You create individual instances by providing an email address, phone number, or user record ID." ただし参加者の例はメール・電話だけ） | 招いたメール・電話が iCloud に無いときの扱い（資料: "CloudKit associates the participant with their iCloud account when they accept the share if they launch the process by tapping or clicking the share URL."） |
| 招待の情報だけで第三者（開発者を含む）が入れるか | **使われる前の一度きりのURLを公開データベースから読めた人は、先に使える**。相手が入れなくなるので気づけ、作った人は外せる | 申し込んだだけでは入れない。作った人の端末が加えるまで入れない。誰の申し込みかを確かめる仕組み（両方の画面に同じ確認番号を出すなど）を足せば、なりすましも防げる | 招いた本人のアカウントだけ（未確認） |
| 作った人の手間 | 発行するだけ（いまと同じ） | 相手が申し込んだとき、作った人がアプリを開いている必要がある | 相手の連絡先を選ぶ |
| 最低対応OS | 作る側に iOS 26 を求めることになる（最低対応OSの変更は利用者の承認） | iOS 17 のまま | iOS 17 のまま |

**確かめる順: A2 → A1 → A3。** 最初に動いたものを使う。
A2 は iOS 17 のまま合言葉を残せて、開発者も招待の情報だけでは入れない。A2 が動かなければ A1（作る側に iOS 26）。
どちらも動かなければ A3（資料がいちばん厚いが、合言葉の招き方が変わる）。

## 4. いまの家計簿（利用者とパートナー）をどうするか

- 資料（CKShare.Participant）: "CloudKit removes all participants if the new permission is none."／資料（removeParticipant）: "You can't mix and match public and private users in the same share."
  → いまの共有を名指しに変えると、パートナーはいったん外れる。**外さずに変える方法は資料に無い**
- 外れているあいだも、作った人の家計のデータはそのまま。パートナーの手元の記録は、入り直すと突き合わせて残す（2章の条件3。実機は未確認）
- **公開前に移せば、入り直しが要るのはこの1組だけ。公開後なら利用者全員。**
- 本番での切り替えは、テスト用アプリでのリハーサル（6章 V8）のあと、改めて承認をもらってから

## 5. D2（App Privacy・ポリシーの言い方）との関係

- 開発者は CloudKit Console で、利用者の家計のデータ（Private / Shared Database）を**直接は見られない**。
  資料（Handling an iCloud container's data）: "If you develop using the same iCloud account to store private data, you can also use the CloudKit Database app to inspect and edit private data."（見られるのは開発者自身の iCloud の分だけ）
- しかし**いまは**、公開データベースの合言葉のレコードに共有のURLが入っていて、開発者は公開データベースを読める
  （同じ資料: "You can use the CloudKit Database app to inspect data within a public iCloud container."）。
  公開の権限が `.readWrite` なので、**そのURLを使えば、開発者も含めて誰でも共有に参加できてしまう**
- そのレコードが残る期間: 使われた・期限が切れたものは、発行した人が共有の画面を開いたときに消す（`tidyIssuedInvites`）。
  開かなければ残る。アプリを消した人・「このiPhone内のデータを削除」をした人の発行したものは、控えが無くなるので残り続ける
- → 「データベースを直接見られない」は言えるが、「招待の情報から共有に参加できない」は**いまは言えない**。
  名指しの形（A2）にすれば、共有のURLだけでは入れないので両方言える（A1 なら、使われる前の一度きりのURLの分が残る）

## 6. 検証の準備（本番と分けて行う）

場所: テスト用アプリ（`Docs/TEST_APP_PLAN.md`。別の Bundle ID・別の CloudKit コンテナ・Development 環境）。
いまの2台（iPhone 13・iPhone SE 第2世代）と、利用者・パートナーの2つの Apple Account を使う。**日常の家計簿には触れない。**

| # | 確かめること | 合格 | 要るもの |
| --- | --- | --- | --- |
| V1 | A2: 相手のユーザーレコードIDから参加者を作れる（相手は発見の許可を出していない） | 作った人の端末で参加者が返り、相手が参加できる | 2台 |
| V2 | A1: iOS 26 の端末で一度きりのURLを作り、相手が参加できる | 参加できる | 2台 |
| V3 | A1: 使われた一度きりのURLで、ほかの人が入れない | 入れない | **3つ目の Apple Account** |
| V4 | 名指しの共有で、前の公開の共有のURLを使っても入れない（前に参加していた相手で試す） | 入れない | 2台 |
| V5 | 作った人が共有をやめると、相手の画面で家計簿が同期しなくなる。相手の手元の写しがどう見えるか記録する | 同期しない | 2台 |
| V6 | 共有し直したあと、前の参加者が古いURL・使った合言葉で入れない | 入れない | 2台 |
| V7 | 外れていたあいだに相手が足した記録・消した記録・レシート画像が、入り直したあと失われず、消した記録は戻らない | すべて合う | 2台 |
| V8 | いまの家計簿のリハーサル: 公開の共有から名指しへ切り替える。相手が外れ、作った人のデータが変わらず、相手が入り直せる | 件数と合計が前後で同じ | 2台 |
| V9 | 公開データベースに残るもの（合言葉・使われた印）と、消えるタイミング | 記録どおり | 2台 + CloudKit Console（テスト用コンテナの Development） |

コードの準備（承認のあと）: 名指しの招き方は、テスト用アプリでだけ動くように分けて作る（本番のアプリの共有は変えない）。
画面や CloudKit に触らない判断の部分は、いまと同じように先に自動テストで押さえる。

## 7. 残るリスク（どの案でも）

- 以前の参加者の端末に残った写しは消せない
- 作った人や相手の Apple Account に入れる人（家族で使っている iPad など）は、その人として家計簿を見られる
- 端末の時計が大きくずれていると、同じ記録を同時に直したときの勝ち負けがずれる（D10 で受け入れた仕様。消した記録が戻らないことと、別々に足した記録が消えないことは、時計に関係なく守る）
- A1 を使うなら、使われる前の一度きりのURLの横取り（気づけるが、防げない）
- 実機で確かめるまでは、どの案も「動く見込み」

## 8. このあと承認が要ること

1. テスト用アプリのための Apple Developer の変更とワークフロー（`Docs/TEST_APP_PLAN.md` 3章）
2. 検証のあと、どの案で作るか（A1 なら、作る側の最低OSの変更も）
3. 本番の共有の方式の切り替えと、いまの家計簿の移行（パートナーが一度外れて入り直す）
