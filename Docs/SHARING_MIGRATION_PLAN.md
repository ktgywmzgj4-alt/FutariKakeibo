# 共有を「参加者を名指しする形」に移す計画（T-048）

2026-10-21 の利用者の回答 ②: **いまの共有方式は変えない。正式公開の前に安全にしたいので、移す方式の設計と検証の準備を進める。**
この文書は設計と、検証の段取りです。

- **既存の共有には何もしていません。** 公開の権限（`.readWrite`）も、参加している人も、データもそのままです
- Production への適用、既存の共有の権限の変更、最低対応iOS（いまは iOS 17）の変更は、**改めて利用者の承認を得てから**
- 準備としてこの版に入れたのは、入り直したときに手元を消さない直し（6章）と、移す前の条件（`ShareMigrationReadiness`）とテストだけ

前提の監査は `Docs/SHARING_SECURITY_AUDIT.md`（いまの形の弱いところ: 共有のURLは共有し直しても変わらない、1人だけ外せない）。

---

## 1. 結論（先に）

1. **おすすめは「その場で切り替える」方式（案A、5章）。** 同じ家計簿（同じ置き場所）のまま、共有を「URLを知っている人なら誰でも」から「名指しした人だけ」に切り替え、いまのパートナーを名指しで入れ直す。データは動かさない
2. 切り替えた瞬間、Appleの仕様で**公開の参加者は全員外れる**（パートナーも）。パートナーのアプリが名指しの招待を受け直すまで、パートナーの同期が止まる。**データは消えない**（作った人のiCloudに残り、パートナーの手元の未送信の記録は、受け直したあとに送られる）
3. うまくいかなければ、作った人が公開の権限を戻せば、**前と同じURL**（変わらない）で今までどおり入れる
4. これから新しく招くときは、「合言葉 → 相手が参加を申し込む → 作った人が承認する」形にする。名指しはアプリの中で分かる相手の利用者ID（ユーザーレコードID）で行うので、**相手のメールアドレスや電話番号は要らず、iOS 17 から使える見込み**。iOS 26 の端末では、Apple の「参加の申し込み」機能も使える
5. どれも**実機での検証が要る**（9章）。とくに「ユーザーレコードIDで名指しできるか」は Apple の説明がメール・電話番号の例しか無く、確かめるまで決められない

---

## 2. Apple が用意している招き方

| 招き方 | 参加できる人 | 招待が漏れたら | 1人だけ外す | iOS | 相手について要るもの |
| --- | --- | --- | --- | --- | --- |
| 公開の共有（**いま**） | URLを知っている人なら誰でも | 誰でも入れる。URLは共有し直しても同じ | できない（全員外すだけ） | 10 から | なし |
| 一度きりのURL（`oneTimeURLParticipant`） | そのURLを最初に使った1人 | 使われる前なら、先に使った人が入る。使われたあとは使えない | できる | 参加者を作るのは 18 から。URLを取り出す Swift の関数は 26 から（Apple の資料の表示） | なし |
| 名指し（`LookupInfo` → `CKFetchShareParticipantsOperation`） | 指定した Apple ID の人だけ | 他人は入れない | できる | 10 から | メールアドレス・電話番号、またはアプリの中で分かるユーザーレコードID |
| 参加の申し込み（`allowsAccessRequests`） | 申し込んだ人のうち、作った人が承認した人 | 承認しなければ入れない。断る・ブロックもできる | できる | 26 から | なし（申し込みに名前と連絡先が付く） |

Apple の説明（原文）:

- `CKShare.Participant`: "Anyone with the URL of a public share can become a participant in that share. [...] For private shares, the owner manages the participants. [...] A participant of a private share can't accept the share unless the owner adds them first. [...] CloudKit removes any pending participants if the owner changes the share's publicPermission. CloudKit removes all participants if the new permission is none."
- `CKShare.removeParticipant(_:)`: "To modify the list of participants, a share's publicPermission must be none. You can't mix and match public and private users in the same share."
- `CKShare.Participant.oneTimeURLParticipant()`: "When a participant's email address / phone number / userRecordID isn't known up-front, you can add a oneTimeURLParticipant() to the share. Once you save the share, you can get a custom invitation link or one-time URL for the added participant via oneTimeURL(for:). Any recipient user can use this custom link to fetch share metadata and accept the share."
- `CKShare.allowsAccessRequests`: "When this property is YES, uninvited users can request access to the share if they discover the share URL. When this property is NO, the server prevents uninvited users from requesting access and does not indicate whether the share exists."
- `CKShare.requesters`: "Approve Requesters: Fetch the participant information by running CKFetchShareParticipantsOperation with the requester's participantLookupInfo. Add the resulting participant to the share. [...] Block Requesters: Use blockRequesters(_:) to block requesters. Blocking a requester prevents them from sending future access requests to the share."
- `CKUserIdentity.LookupInfo`: "You create individual instances by providing an email address, phone number, or user record ID."（`init(userRecordID:)` は iOS 10 から）

## 3. `oneTimeURLParticipant` が保証すること・しないこと

**保証すること（Apple の説明から言えること）**

- 名指しの共有（公開の権限 `.none`）で使う。共有のふつうのURLだけでは入れない
- そのURLで入れるのは1人（参加者の枠が1つ）。使った人がその枠の参加者になる
- 入った人は参加者の一覧に出る。名指しの共有なので、作った人がその人だけを外せる

**保証しないこと**

- **使う人が本当の相手かどうか。** 説明は "Any recipient user can use this custom link"。URLを最初に使った人が入る。使われる前に漏れれば、先に使った他人が入る（いまの合言葉と同じ弱さ）
- URLの期限（説明が無い。確かめる）
- 使われたあと、本当に二度と使えないか。使われる前に作った人が取り消せるか（説明は「一度きり」だけ。確かめる）

**いまの合言葉との違い:** いまは「1回だけ」をアプリの中で守っている（使われた印）。一度きりのURLなら、Apple のサーバーが守る。
URLを知っていれば入れる弱さ（共有し直しても同じURL）も無くなる。ただし本人確認にはならないので、作った人の承認（4章の申し込み）と組み合わせる。

## 4. 一度きりのURLと、Apple ID を指定する招待の違い

| | 一度きりのURL | Apple ID を指定（名指し） |
| --- | --- | --- |
| 誰が入れるか | URLを最初に使った人 | 指定した Apple ID の人だけ |
| 漏れたとき | 使われる前なら他人が入れる | 他人は入れない |
| 相手について要るもの | なし | メール・電話番号、またはユーザーレコードID |
| 相手のプライバシー | 連絡先を預からない | メール・電話番号で指定するなら、その連絡先をアプリが扱う。ユーザーレコードIDならアプリの中だけの番号で済む |
| iOS（作る側） | 18 から（URLを取り出す Swift の関数は 26 から） | 10 から |

**このアプリでの使い方の案:** 合言葉で、相手のアプリが「参加の申し込み」を公開データベースに置く（中身は相手のユーザーレコードIDだけ。家計のデータは置かない）。
作った人のアプリが申し込みを見つけたら「〇〇さんが参加を申し込んでいます。参加させますか？」と聞き、承認したら、そのユーザーレコードIDで名指しする。
**合言葉が漏れても、作った人が承認しなければ入れない。** 相手の連絡先も要らない。作った人がアプリを開くまで参加が終わらない、という待ちは増える。

## 5. iOS 17・18・26 での動作条件（最低対応は iOS 17 のまま変えない）

| 機能 | iOS 17 | iOS 18〜25 | iOS 26 |
| --- | --- | --- | --- |
| いまの公開の共有 | ○ | ○ | ○ |
| 名指し（ユーザーレコードID・メール・電話） | ○ | ○ | ○ |
| 一度きりの参加者を作る | × | ○ | ○ |
| 一度きりのURLを取り出す（Swift） | × | Apple の資料は「26 から」（Mac Catalyst だけ 18）。**18 で使えるかは CI のコンパイルで確かめる** | ○ |
| 参加の申し込み・承認・断る・ブロック | × | × | ○ |

- 招き方を決めるのは、**共有を保存する作った人の端末**の iOS。作った人が iOS 17 なら、名指し（ユーザーレコードID）と申し込みの承認を自前で作る形になる
- 参加する側の iOS の条件（例: iOS 17 の端末で一度きりのURLを受けられるか）は、説明が無いので確かめる
- 利用者の2台（iPhone 13・iPhone SE 第2世代）は、どちらも iOS 26 に対応している機種。ただし入っている版はそれぞれ確かめる

## 6. パートナーが入り直すときのデータの保護（この版で準備したもの）

| データ | 入り直したとき | この版で |
| --- | --- | --- |
| 手元にしか無い支出・収入（外れていたあいだに足した・送れていなかった） | 残して、次の同期で送る（iCloudに無い・iCloudより新しいものだけ） | 第1段階で入れた（同じ置き場所なら置き換えない） |
| 手元の削除印 | 残して送る。消した支出は戻らない | 同上 |
| レシート画像の送信待ち | 残して、次の同期で送る | 同上 |
| 家計簿の設定（名前・予算・覚えた店・定期支出） | **新しいほうを残す**（同期と同じ決まり） | **この版で直した。** 以前は iCloud 側で置き換えていたので、外れていたあいだの設定の変更が消えていた |
| 写した家計簿に入り直す（案B） | **家計簿のID（`Household.id`）が同じなら同じ家計簿**として突き合わせる | **この版で足した。** 置き場所が変わっても、手元にしか無い記録を消さない |

テスト: `SharingMigrationPreparationTests`（写した家計簿でも手元を残す・別の家計簿は置き換える・新しい設定を残す）、`RejoinSnapshotTests`（第1段階）。

**移す前の条件**（`ShareMigrationReadiness`、まだ画面では使わない）: 作った人の端末であること、5分以内に同期が成功していること、送れていないレシート画像が無いこと。
パートナーの端末の同期が済んでいるかは、この端末からは分からないので、移す画面でパートナーに「同期を済ませる」を押してもらう。

## 7. 移し方の案

### 案A（おすすめ）: その場で切り替える

1. **確かめる:** 作った人の端末で `ShareMigrationReadiness` が空。パートナーの端末でも同期を済ませてもらう
2. **パートナーを選ぶ:** 参加者の一覧から、作った人がパートナーを選ぶ（知らない人は選ばない）。選んだ人のユーザーレコードIDから名指しの参加者を作る（`LookupInfo(userRecordID:)` → `CKFetchShareParticipantsOperation`、読み書き）
3. **切り替える（1回の保存）:** 公開の権限を `.none` にし、名指しの参加者を足す。Apple の仕様で公開の参加者は全員外れ、パートナーは名指しの招待（まだ受けていない）になる。知らない人は名指ししないので戻らない
4. **パートナーが受け直す:** パートナーのアプリが「入れなくなった」ことに気づいたら、共有のURLで招待を受け直す。置き場所が同じなので手元は消えない（6章）。
   URLの渡し方は2つ: (a) 作った人のアプリが、そのパートナー向けの合言葉を自動で出す。(b) 参加したときに共有のURLを手元に控えておき、自動で受け直す（次の段階で足す）
5. **元に戻す:** 受け直せないときは、作った人が公開の権限を `.readWrite` に戻す。URLは前と同じなので、パートナーは今までどおり入れる

- よいところ: データを動かさない（レシート画像も）。新しい置き場所を作らない。iOS 17 で動く見込み
- 気をつけること: 切り替えてから受け直すまで、パートナーの同期が止まる。ユーザーレコードIDで名指しできるかは確かめが要る（できなければメール・電話番号で名指しする。その場合は相手の Apple ID の連絡先を入れてもらう）

### 案B: 新しい置き場所に写して、並べて動かす

いまの共有を残したまま、新しい置き場所（ゾーン）に家計簿を写し、名指しの共有（一度きりのURL）で招く。パートナーが新しい共有に入って同期できたのを確かめてから、古い共有をやめる。

- よいところ: **古い共有を外さずに準備できる。** 失敗しても古い共有が残る
- 気をつけること: 全部の記録とレシート画像を写す必要がある（写し損ねの危険、時間）。家計簿のIDを同じにして写す（6章の準備が効く）。一度きりのURLの Swift の関数は iOS 26 から（5章）

### 案C: Apple の共有画面（`UICloudSharingController`）でメッセージ・メールから名指しで招く

相手のメールか電話番号が要る。合言葉とは別の入口になる。iOS 17 から使える。アプリには、使っていないこの画面の部品が残っている（`CloudSharingView`）。

## 8. 失敗したときの戻し方

| 起きたこと | 戻し方 | データ |
| --- | --- | --- |
| 切り替えの保存が失敗した | 何も変わらない（1回の保存でまとめて行う） | 変わらない |
| パートナーが受け直せない | 作った人が公開の権限を戻す（同じURLで入れる） | 変わらない（置き場所が同じ） |
| 知らない人がいた | 切り替えで外れ、名指ししないので戻らない | 変わらない |
| 案Bで写し損ねた | 古い共有を使い続ける。新しい置き場所は消さずに残す（消すのは別の承認） | 古いほうが本体のまま |

どの場合も、**どちらの端末でも手元の記録は消さない**。

## 9. 第三者の参加を防ぐ・見つける・取り消す

| | いま | 移したあと（案A） |
| --- | --- | --- |
| 防ぐ | 合言葉は1回・1日。共有のURLはアプリの画面に出さない | 名指しの人しか入れない（URLだけでは入れない）。新しく招くときは作った人の承認。iOS 26 では申し込みを断る・ブロック |
| 見つける | 共有の画面の参加者と人数、ふたりより多ければ警告 | 同じ。iOS 26 では申し込みの一覧 |
| 取り消す | 共有をやめる（全員外れる。URLは同じまま） | **その人だけ外す**（`removeParticipant`） |

## 10. 検証の段取り（Production には触らない）

Development の環境（CloudKit の試験用の場所）で、テスト用の Apple ID を2〜3個使って確かめる。

- ビルド: `ios-dev-build.yml`（Development の CloudKit につながるビルド）。**このワークフローは、Apple Developer の Ad Hoc プロファイルを作り直し、端末を登録する。** 動かす前に利用者の承認を得る
- 確かめること:
  1. ユーザーレコードIDで名指しの参加者を作れるか（`LookupInfo(userRecordID:)`）。相手の設定（見つけてもらうことの許可など）が要るか
  2. 1回の保存で「公開の権限を `.none` にする」と「名指しの参加者を足す」を同時にできるか
  3. パートナーが同じURLで受け直せるか。受け直すまで、パートナーのアプリがどう見えるか
  4. 受け直したあと、未送信の支出・削除・レシート画像・設定が送られるか（6章）
  5. 公開の権限を戻すと、パートナーが前のURLで入れるか
  6. 一度きりのURL: iOS 18 の端末で作れるか（Swift の関数の対応版）、使ったあと無効になるか、期限があるか、iOS 17 の端末で受けられるか
  7. iOS 26 の参加の申し込み: 申し込み → 承認 → 参加、断る、ブロック
- 一度きりのURLの関数が iOS 18 で使えるかは、実機の前に CI のコンパイルでも確かめられる（`#available(iOS 18.0, *)` の中で呼んで、通るかどうか）

## 11. 次に承認をいただくこと

1. Development での検証を始めてよいか（`ios-dev-build.yml` は Ad Hoc プロファイルの作り直しと端末の登録をする。テスト用の Apple ID の用意）
2. 検証のあと、どの案で Production に適用するか（案Aなら、パートナーが一度外れて受け直す）
3. 新しい招き方（申し込みと承認）の画面を作るか
