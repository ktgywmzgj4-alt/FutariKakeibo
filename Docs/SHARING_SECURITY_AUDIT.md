# 共有と取り戻しの安全の監査（2026-10-19）

正式公開の前に、ふたりの家計簿の共有（合言葉・CloudKitの共有）と、アプリを入れ直したときの
取り戻しを見直した記録です。台帳は `tasks.json` の T-040（共有）・T-041（取り戻し）・T-043（説明の文）。

- 調べたもの: このリポジトリのコード（`CloudKitSyncService.swift`・`AppStore.swift`・`ShareInvite.swift` ほか）と、
  Appleの公式ドキュメント（下に原文を引用）
- **実機では確かめていません。** 実機の確認は最後の「実機での確認」に、利用者にお願いする項目として並べています
- CloudKit の Production のスキーマ（レコードの型・項目・権限・索引）は**変えていません**。既存のデータも消していません

---

## 1. 結論（先にまとめ）

1. **家計のデータ（支出・収入・予算・覚えた店・レシート画像）は、公開の場所には置いていません。**
   家計簿を作った人のiCloudの中（Private Database）にあり、共有に参加した人だけが読み書きできます。
2. **ただし、この共有は「共有のURLを知っている人なら誰でも参加できる」形です**（`publicPermission = .readWrite`）。
   合言葉は、そのURLを1日だけ引けるようにする鍵です。合言葉かURLが知らない人に渡ると、その人は参加でき、
   家計簿を読むことも書き換えることもできます。
3. 監査で、**使った合言葉が1日のあいだ何度でも使えた**ことが分かりました（画面には「誰かが参加すると無効」と
   書いてあった）。直しました。いまは、先に使った1人だけが参加でき、2人目は断られます。
4. **アプリの中の説明に誤りがありました**（「公開データベースは使いません」）。合言葉は公開データベースに
   置いているので、家計のデータと合言葉を分けて書き直しました。
5. 共有に**誰が参加しているかを見られるようにしました**。ふたりより多ければ知らせ、家計簿を作った人は共有をやめられます。
6. 残る課題: **共有のURLは、共有をやめて始め直しても変わりません**（Appleの説明）。URLそのものを控えている人がいると、
   また入れます。1人だけを外すこともできません。根本から直すには「参加者を名指しする共有」に移る必要があり、
   いまのパートナーが一度外れるので、**利用者の判断と実機での確認が要ります**（7章）。
7. 取り戻しは、**iCloudに置いてあった家計簿だけ**が戻ります。iPhoneの中だけで使っていた家計簿は、アプリを消すと戻りません。
   家計簿が2つ以上見つかったときに古いほうへ戻ってしまう問題を直しました（選ぶ画面を出す）。

---

## 2. ことば

| ことば | 意味 |
| --- | --- |
| iCloud / CloudKit | Appleのサーバーにデータを置く仕組み。このアプリはCloudKitを使う |
| Private Database（プライベートの場所） | その人のiCloudの中で、その人だけが読める場所。家計簿を作った人の家計のデータはここ |
| Shared Database（共有の場所） | 他の人から共有されたものが見える場所。参加した人の端末からは、家計簿はここに見える |
| Public Database（公開データベース） | このアプリの利用者なら誰でも読める場所。**合言葉だけ**をここに置く |
| CKShare（共有） | 「このデータをこの人たちに見せる」という設定のレコード。共有のURLを持つ |
| 公開の権限（`publicPermission`） | 共有のURLを知っている人に、何を許すか。このアプリは「読み書き」（`.readWrite`） |
| 参加者 | 共有に入った人。公開の権限で入った人は「公開の参加者」 |
| 合言葉 | 8文字の文字列。公開データベースに「合言葉 → 共有のURL」の対応を1日だけ置く |
| 削除印（tombstone） | 支出を消したときに残す「消した」という印。古い端末から消した支出が戻らないようにする |

---

## 3. いまの仕組み

### 合言葉を発行する（家計簿を作った人）

1. 家計のデータを、自分のiCloudのPrivate Databaseのゾーンへ送る（家計簿のレコードの下に支出・収入・レシート画像）
2. 家計簿のレコードに共有（CKShare）を付ける。公開の権限は「読み書き」（`CloudKitSyncService.sharePublicPermission`）
3. 共有のURLを受け取る
4. 公開データベースに `invite-<合言葉>` というレコードを1件置く。中身は **共有のURL と 期限（24時間後）だけ**
5. 発行した合言葉を端末に控える（`AppSnapshot.issuedInvites`。後で消すため）

合言葉は 0・O・1・I・L を除いた31文字から8文字。iPhoneの暗号用の乱数（`randomElement()` の既定）で作ります。
組み合わせは 31^8 ≒ 8.5×10^11 通りです。

### 合言葉で参加する（相手）

1. 合言葉から `invite-<合言葉>` と「使われた印」`invite-used-<合言葉>` を読む
2. 印があり、作ったのが自分でなければ「もう使われています」で断る。期限が切れていれば断る
3. **印を作る（`claimInvite`）。** 同じ名前のレコードは2つ作れないので、先に作れた1人だけが進める
4. 共有のURLから参加する（`CKAcceptSharesOperation`）。家計簿は相手の端末のShared Databaseに見える
5. 手元の家計簿を、共有先の家計簿に置き換える（画面で先に注意している）

### 後片付け（発行した人の端末）

同期のたび（アプリを開いているあいだ30秒ごと）と共有の画面を開いたときに、控えた合言葉を見る。
使われた・期限が切れた・発行し直して要らなくなった合言葉は、公開データベースから消す（`tidyIssuedInvites`）。
**合言葉のレコードを消せるのは、発行した本人だけ**なので、この仕事は発行した端末がする。

---

## 4. Appleの説明（原文）

判断の根拠にしたAppleのドキュメントです。

- `CKShare.publicPermission`（https://developer.apple.com/documentation/cloudkit/ckshare/publicpermission）
  > Setting this property's value to be more permissive than none allows any user with the share's URL to join.
  > CloudKit removes all public participants when you save the share if you set the property's value to none.
- `CKShare.Participant`（https://developer.apple.com/documentation/cloudkit/ckshare/participant）
  > Anyone with the URL of a public share can become a participant in that share. Participants of a public share
  > assume the publicUser role. For private shares, the owner manages the participants. [...] A participant of a
  > private share can't accept the share unless the owner adds them first. [...] CloudKit removes any pending
  > participants if the owner changes the share's publicPermission. CloudKit removes all participants if the new
  > permission is none.
  >
  > Participants with write permissions can modify or delete any record that you include in the share. However,
  > only the owner can delete a shared hierarchy's root record.
- `CKShare.removeParticipant(_:)`（https://developer.apple.com/documentation/cloudkit/ckshare/removeparticipant(_:)）
  > To modify the list of participants, a share's publicPermission must be none. You can't mix and match public
  > and private users in the same share.
- `CKShare.url`（https://developer.apple.com/documentation/cloudkit/ckshare/url）
  > This URL is stable and persists across shares and reshares of the same root record.
- `CKShare`（https://developer.apple.com/documentation/cloudkit/ckshare）
  > If a participant attempts to delete the share, CloudKit removes the participant. The share remains active for
  > all other participants. [...] CloudKit limits the number of participants in a share to 100
- `CKContainer.publicCloudDatabase`（https://developer.apple.com/documentation/cloudkit/ckcontainer/publicclouddatabase）
  > The contents of the public database are readable by all users of the app, and users have write access to the
  > records, and other objects, they create. The public database's contents are visible in the developer portal,
  > where you can assign roles to users and restrict access as necessary.
- `CKDatabase`（https://developer.apple.com/documentation/cloudkit/ckdatabase）
  > CloudKit requires an iCloud account for writing to the public database so it can identify the authors of any changes.
- `CKShare.Participant.oneTimeURLParticipant()`（https://developer.apple.com/documentation/cloudkit/ckshare/participant/onetimeurlparticipant()）
  > When a participant's email address / phone number / userRecordID isn't known up-front, you can add a
  > oneTimeURLParticipant() to the share. Once you save the share, you can get a custom invitation link or one-time
  > URL for the added participant via oneTimeURL(for:).

  ページの対応版の表示は、`oneTimeURLParticipant()` が iOS 18.0、`oneTimeURL(for:)` が iOS 26.0（Mac Catalyst 18.0）と分かれている。
- `CKShare.allowsAccessRequests`（iOS 26.0 から。https://developer.apple.com/documentation/cloudkit/ckshare/allowsaccessrequests）
  > When this property is YES, uninvited users can request access to the share if they discover the share URL.
- App Store Reviewガイドライン 5.1.1(i)（https://developer.apple.com/app-store/review/guidelines/）
  > The privacy policy must clearly and explicitly: Identify what data, if any, the app/service collects, how it
  > collects that data, and all uses of that data.

---

## 5. 問われたことへの答え

### 5-1. 第三者が家計データにアクセスできる条件

次のどれかに当てはまる人は、共有に参加して、家計簿を読み書きできます。

| 条件 | 起きうる場面 | 守り |
| --- | --- | --- |
| まだ使われていない合言葉を、期限（24時間）のうちに知った | 画面をのぞかれた、送ったメッセージが他の人に見られた | 1回だけ（先着1人）。使われたら相手に「もう使われています」と出るので気づける |
| 共有のURLそのものを知っている | 公開データベースの合言葉のレコードを、合言葉を使って直接読んだ（技術のある人）。前に参加していた人（参加者は共有を読めるのでURLも分かる） | アプリの画面にURLは出さない。使われた合言葉のレコードは発行した端末が消す。**共有を始め直してもURLは同じ**（残る課題） |
| 家計簿を作った人・参加した人のApple IDに入れる | Apple IDの乗っ取り | アプリの範囲外（Apple IDの2ファクタ認証） |

当てはまらない人は読めません。

- 公開データベースにある合言葉のレコードは、**合言葉（レコードの名前）を知っていないと読めない**。
  このアプリは合言葉を一覧で探す処理を持たず、`ShareInvite` 型に検索の索引を付ける手順もない
  （**Production の索引は CloudKit Console で確かめる。** 8章）
- 公開データベースを読めるのは、このアプリ（署名されたもの）か、開発者がCloudKit Consoleで作るAPIトークンを持つ人だけ。
  他の開発者のアプリからこのアプリのiCloudの場所は読めない
- 家計のデータは公開データベースに置いていない（`publishInvite` が入れるのは共有のURLと期限だけ）

### 5-2. 合言葉を推測・入手・悪用されるリスク

- **推測:** 8.5×10^11 通り。1回試すごとにiCloudへの問い合わせが要る。1日のあいだ毎秒100回試し続けても（864万回）、
  有効な合言葉1つに当たる見込みは約10万分の1。アプリの画面からは1回ずつ手で入れるしかない。**推測は現実的でない**
- **入手:** 現実的なのはこちら。合言葉はメッセージで送ることが多い（共有の画面の「合言葉を送る」）。送った履歴は残るが、
  使われたあとは役に立たない。**使われる前に他の人が見ると、その人が先に参加できる**。そのときは相手に
  「もう使われています」と出るので、発行した人に知らせ、共有の画面で参加者を確かめる
- **悪用:** 参加した人は、アプリの画面でできることは全部できる（支出・収入の追加・直し・削除、レシート画像を見る、
  名前や予算を見る）。Appleの説明のとおり、書き込みの権限を持つ参加者は、家計簿のレコード（根）以外のどのレコードも直せる・消せる。
  消された支出は削除印で消えたことになり、もう一方の端末からも消える

### 5-3. 公開の権限と、参加者ごとの権限の違い

- **公開の権限（`publicPermission`）**: 共有のURLを知っている人すべてに与える権限。このアプリは「読み書き」。
  URLを開いて参加した人は「公開の参加者」（`publicUser`）になる
- **参加者ごとの権限**: 「参加者を名指しする共有」（公開の権限が `.none`）でだけ使える。家計簿を作った人が
  参加者を1人ずつ足し、1人ずつ外せる。名指しされていない人はURLを知っていても参加できない
- **2つは混ぜられない**（Appleの説明）。公開の参加者を1人だけ外すことはできず、公開の権限を `.none` にすると
  公開の参加者が**全員**外れる。いまのパートナーも外れる

### 5-4. レコードの権限と、検索できるか

| 場所 | レコード | 読める人 | 書ける・消せる人 | 検索 |
| --- | --- | --- | --- | --- |
| Private Database（作った人） | 家計簿・支出・収入・レシート画像 | 作った人と共有の参加者 | 作った人と「読み書き」の参加者（根の家計簿は作った人だけが消せる） | 共有の中だけ |
| Public Database | `invite-<合言葉>`（共有のURL・期限） | このアプリの利用者なら誰でも（名前を知っていれば） | 発行した人だけ | 索引が無ければ一覧できない（8章で確かめる） |
| Public Database | `invite-used-<合言葉>`（期限だけ） | 同上 | 作った人（参加した人）だけ | 同上 |

Public Database の「誰でも読める・サインインした人なら作れる・作った人だけが書き換えられる」は、Appleの説明にある初期の形です。
CloudKit Console で変えていないことを確かめてください（8章）。

### 5-5. 招待の有効期限と、使ったあとの無効化

- **期限:** 24時間（`ShareInvite.lifetime`）。期限は**アプリが比べる**（`resolveInvite`）。CloudKitの公開データベースには
  レコードを時間で消す仕組みが無いので、期限が切れたレコードは、発行した端末が次にアプリを開いたときに消す
- **使ったあと:** 以前は、参加した人が合言葉のレコードを消そうとして失敗していた（消せるのは作った人だけ）。
  そのため**使った合言葉が期限まで何度でも使えた**。いまは、参加する前に「使われた印」を作り、印があれば断る。
  印は1つしか作れないので、ほぼ同時に2人が入れても先着1人。発行した端末は印を見つけると合言葉のレコードを消す
- **限界:** 期限と印の確認はアプリの中で行う。技術のある人が、まだ消されていない合言葉のレコードからURLを直接読めば、
  アプリの確認を通らずに参加できる。これを防ぐには「参加者を名指しする共有」が要る（7章）

### 5-6. 不正な参加を防げるか

- **防げるようになったこと:** 使った合言葉での2人目の参加。期限の切れた合言葉での参加（アプリから）
- **気づけるようになったこと:** 共有の画面に参加している人と人数を出す。ふたりより多ければ赤字で知らせる
- **止められること:** 家計簿を作った人は「共有をやめる（全員が外れます）」で、参加している人を全員外せる。家計のデータは消えない
- **まだできないこと:** 参加する前に家計簿を作った人が承認すること。知らない人だけを外すこと。共有のURLを変えること（7章）

### 5-7. App Storeへの公開で問題にならないか

- 公開の共有は、Appleが用意している仕組みです（UICloudSharingControllerにも「リンクを知っている人なら誰でも」の選択肢がある）。
  それ自体が審査で禁止されているとは考えていません
- 問題になりやすいのは、**プライバシーの説明と実際の動きの食い違い**です（ガイドライン 5.1.1(i)）。
  「公開データベースは使いません」は事実と違っていたので直しました（6章）
- 正式公開の前に、プライバシーポリシーの公開URL・運営者名・問い合わせ先が要ります（`Docs/PRIVACY_POLICY_REQUIREMENTS.md`）
- 正式公開の前に、「参加者を名指しする共有」へ移るかを決めることを勧めます（7章）

---

## 6. 見つけた問題と、やったこと

深刻度: **高** = ふつうの使い方で、家計のデータが他人に渡る・消える・説明が事実と違う。
**中** = 合言葉やURLが漏れたときなど、条件がそろえば起きる。**低** = 技術のある人が狙ったとき、または影響が小さい。

| # | 深刻度 | 問題 | やったこと |
| --- | --- | --- | --- |
| S1 | 高 | 使った合言葉が1日のあいだ何度でも使えた。画面には「誰かが参加すると無効」と書いてあった | 参加する前に「使われた印」を作る（先着1人）。印があれば断る。発行した端末が合言葉のレコードを消す |
| S2 | 高 | アプリの「データとプライバシー」に「公開データベースは使いません」。設計の文書にも「Public Database不使用」「CKShareの公開権限なし」 | 家計のデータ（Private/Shared Database）と合言葉（Public Database）を分けて書き直した。テストで押さえた |
| S3 | 中 | 共有に誰が参加しているかを見る手段が無かった。知らない人が入っても気づけない | 共有の画面に参加者と人数。ふたりより多ければ赤字で知らせ、作った人は共有をやめられる |
| S4 | 中 | 共有のリンク（iCloudの招待）を開くと、確かめずに手元の家計簿が置き換わった。知らない人から届いたリンクでも起きる | すでに別の家計簿があるときは、置き換わることと、知らない人のリンクに参加しないことを伝えてから参加する |
| S5 | 中 | 共有のURLは、共有をやめて始め直しても変わらない（Appleの説明）。公開の参加者を1人だけ外せない | **残る課題（7章）。** 共有をやめる確認の文で、リンクが前と同じになることを正直に書いた。「新しいURLになる」と書いていたコメントを直した |
| S6 | 低 | 期限の切れた・使われた合言葉のレコード（共有のURL入り）が、公開データベースに残り続けた | 発行した端末が、同期のたびに消す。**この版より前に発行した合言葉は、端末に控えが無いので消せない**（8章の任意の掃除） |
| S7 | 低 | ほぼ同時に2人が同じ合言葉を入れると、2人とも参加できた | 印は1つしか作れないので先着1人 |
| S8 | 低 | 期限は端末の時計で比べる。時計をずらすと期限切れの合言葉を通せる | 使われた印と、発行した端末の後片付けで、1回に限られる。根本は7章 |
| S9 | 低 | 「使われた印」は参加した人が作るので、発行した人には消せない | 印には期限しか入れない（共有のURLは入れない）。ごく小さなレコードが残る |
| R1 | 高 | 入れ直して「iCloudから戻す」を押すと、家計簿が2つあるとき（参加する前に自分でも合言葉を発行していた人）、古いほうに戻ることがあった | 2つ以上なら一覧を出して選んでもらう。最近まで使われていたものが先頭 |
| R2 | 低 | 同期の突き合わせで、同じIDの記録が2つあるとアプリごと落ちる書き方だった（`Dictionary(uniqueKeysWithValues:)`） | 新しいほうを残すようにした（`SyncMerge`）。突き合わせを画面から切り離してテストした |
| R3 | 中 | 入口に「このiPhoneを前にも使っていたなら、ここから戻せます」。iPhoneの中だけで使っていた家計簿は戻せない | 「iCloudに置いてあった家計簿なら戻せる。iPhoneの中だけの家計簿は戻せない」と書いた。共有の画面にも、アプリを消すと戻せないことを書いた |
| R4 | 中 | 同じ家計簿に入り直すと（共有をやめられて外れたあと、同じ家計簿の合言葉をもう一度入れたとき）、手元が丸ごと置き換わり、手元にしか無い記録（外れていたあいだに足した・送れていなかった）が消えた | 同じ家計簿なら置き換えずに突き合わせ、手元の記録と削除印・レシート画像の送信待ちを残して、次の同期で送る（`AppStore.snapshotAfterJoining`）。別の家計簿なら、これまでどおり置き換える |

**変えていないもの:** 共有の公開の権限（`.readWrite`）、CloudKitのレコードの型と項目、既存のデータ、合言葉の長さと期限、
ファイルの版（`AppSnapshot.currentSchemaVersion` は 4 のまま。前のビルドに戻しても家計簿が開ける）。

### 既存の利用者への影響

- **いまふたりで使っている家計簿は、そのまま使えます。** 共有の権限を変えていないので、パートナーは外れません
- 発行した人と参加する人の**どちらかが前の版**のとき:
  - 参加する人が前の版: 印を作らないので、その合言葉は期限まで使えたまま（前と同じ）。新しい版の人は、印が無い合言葉なら使える
  - 発行した人が前の版: 合言葉のレコードを消さない（前と同じ）。新しい版の参加者が作った印で、2人目の参加は断られる
  - どちらの組み合わせでも、参加そのものは前と同じように動く
- 端末に残すファイルに「発行した合言葉の控え」が増えた。前の版のアプリはこの項目を読み飛ばす

---

## 7. 残る課題: 「参加者を名指しする共有」への移行（提案。未実施）

**2026-10-21: 利用者の回答は「いまは変えない。設計と検証の準備は進める」。** 設計・iOSごとの条件・データの保護・戻し方・検証の段取りは
`Docs/SHARING_MIGRATION_PLAN.md` にまとめた（この章より新しい）。この章は監査のときの最初の案として残す。

**なぜ要るか:** いまの形では、共有のURLを知っている人は、共有が続くかぎり（やめて始め直しても）参加できます。
知らない人だけを外すこともできません。

**移行のしかた（案）:**

1. 共有の公開の権限を `.none` にする（参加者を名指しする共有）
2. 合言葉を発行するときに、`oneTimeURLParticipant()` で「1回だけ使えるURL」の参加者を1人足し、そのURLを合言葉に結びつける
   （いまの `ShareInvite` 型の `shareURL` 項目に入れるので、**CloudKitのスキーマは変わらない見込み**）
3. 合言葉で参加する流れは、利用者から見て今と同じ。URLは1回使うと使えなくなる
4. 知らない人が入ったら、その人だけを外せる（`removeParticipant`）

**いまのパートナーへの影響:** 公開の権限を `.none` にした時点で、Appleの説明どおり**いまのパートナーは外れます**。
新しい合言葉で入り直してもらう必要があります。

- 家計のデータは消えません（作った人のiCloudに残る）
- パートナーの端末にまだ送れていない記録があっても、入り直したときに残る見込みです。この版で、同じ家計簿に
  入り直すときは置き換えずに突き合わせるようにしました（R4）。ただし、家計簿の設定（予算・覚えた店など）は
  iCloudのほうに合わせるので、外れていたあいだの設定の変更は残りません。移行の前に実機で確かめます
- 移行は、ふたりがそろっているときに、画面の案内に沿って1回だけ行う形にします

**確かめが要ること（実機）:**

- `oneTimeURL(for:)` の対応版の表示が iOS 26.0 になっている。iOS 18 で使えるか、iOS 17 の端末が1回だけのURLで参加できるか
- 最低対応OS（いまは iOS 17）を上げるかどうか（利用者の判断）
- iOS 26 以降なら、参加の申し出をアプリで承認する形（`allowsAccessRequests`）も選べる

**判断していただきたいこと:** この移行を正式公開の前に行うか。行うなら、別の段階（別のPR）で、実機2台での確認と
いっしょに進めます。

ほかに考えた案と、選ばなかった理由:

- 共有をやめたときに家計簿の根のレコードを作り直してURLを変える: 全部の記録を付け替えることになり、
  途中で失敗すると記録がばらばらになる。データを失う恐れがあるのでやらない
- 合言葉の期限を短くする（例: 1時間）: 推測の見込みは小さくなるが、すでに十分小さい。相手に届くまで時間がかかると
  使えなくなるので、いまは変えない

---

## 8. CloudKit Console で確かめてほしいこと（読むだけ。何も変えないでください。T-049）

2026-10-21 に利用者が「読むだけの確認」を承認。**Production のスキーマ・索引・権限・レコード・トークンは変えない・消さない。**
画面の名前は Apple の説明（CloudKit Database app）に合わせた。

### 手順

1. ブラウザで https://icloud.developer.apple.com/ を開き、Apple Developer のアカウントでサインインする
2. 「CloudKit Database」を開く
3. 画面の上で、コンテナ `iCloud.jp.aikawa.futarikakeibo` を選ぶ
4. 環境の切り替えを **Production** にする（Development のままだと、試験用の設定を見てしまう）
5. 左の **Schema → Indexes**: 一覧から `ShareInvite` の行を探し、種類が **QUERYABLE** の索引があるかを見る（とくに `recordName`）。
   `Expense`・`Income` に `recordName` の QUERYABLE があるのは正常（アプリの同期が使う）
6. 左の **Schema → Security Roles**: `ShareInvite` の権限を見る。初期は「World（だれでも）: Read」「Authenticated（サインインした人）: Create」「Creator（作った人）: Write」
   （Apple のスキーマ言語の説明では、公開データベースの型の初期は `GRANT READ TO "_world"`・`GRANT CREATE TO "_icloud"`・`GRANT WRITE TO "_creator"`）
7. 左の **Settings → Tokens & Keys**: API Token と Server-to-Server Key の一覧を見る。あれば**名前と作成日だけ**を控える（トークンの値は控えない・送らない）
8. 何も押さずに閉じる（Save・Delete・Deploy は押さない）

### 結果の見方（Claude が評価する）

| 見たもの | 前提どおり | 前提と違ったら | 深刻度と対策（いずれも利用者の承認のあと） |
| --- | --- | --- | --- |
| `ShareInvite` の QUERYABLE 索引 | 無い | ある | **高。** このアプリの場所に入れる人（改造したアプリ・APIトークンを持つ人）が、合言葉を知らなくても全部の招待（共有のURL入り）を一覧できる。索引を外す（Production のスキーマ変更） |
| `ShareInvite` の権限 | 上の初期のまま | World や Authenticated に Write がある | **高。** 他人が招待を書き換え・消せる（別の共有のURLに差し替えられる）。初期に戻す（Production の変更） |
| API Token・Server-to-Server Key | 無い、または自分で作ったと分かるもの | 心当たりの無いものがある | **中。** Web から公開データベースを読める（合言葉を知っていれば招待が読める。QUERYABLE があれば一覧も）。使っていなければ取り消す |

前提どおりなら、追加の対策は要らない（いまの守りは 5〜6章のとおり）。

### 2026-10-21 の結果（利用者が Production を読むだけで確認。変更なし）

| 見たもの | 結果 | 評価 |
| --- | --- | --- |
| `ShareInvite` の QUERYABLE 索引 | 無い | 前提どおり。合言葉を知らない人は、招待を一覧できない |
| `Expense`・`Income` の QUERYABLE 索引 | ある | 前提どおり（アプリの同期が使う）。この2つの型はプライベート・共有のデータベースにしか置かないので、他人からは読めない |
| API Token・Server-to-Server Key | どちらも無い | 前提どおり。Web から公開データベースを読む入口は無い |
| `ShareInvite` の権限 | 役割の名前が写っていない画面で、Read だけに印 | **全部の役割は、まだ。** 下の「役割ごとの見方」で確かめる（T-051） |

ここまでで、追加の対策は要らない。

### 役割ごとの見方（T-051。読むだけ。Save は押さない）

1. 上の手順の 1〜4 と同じ（環境は Production）
2. 左の **Schema → Security Roles** を開く。役割の一覧が出る。初めからある役割は3つ
   （画面では `_world`・`_icloud`・`_creator`、または World・Authenticated・Creator と出る）。**3つ以外の役割があれば、その名前も控える**
3. 役割を1つずつ押し、出てくる型の一覧で `ShareInvite` の行を探して、**Create・Read・Write のどれに印があるか**を控える
4. 全部の役割を見終えたら、何も押さずに閉じる

| 役割 | 前提（初期のまま） | 前提と違う印 |
| --- | --- | --- |
| World（`_world`、だれでも） | Read だけ | Create・Write |
| Authenticated（`_icloud`、iCloud にサインインした人） | Create（Read もあってよい） | **Write** |
| Creator（`_creator`、そのレコードを作った人） | Write（Read もあってよい） | Write が無い（発行した人が、自分の合言葉を片付けられないだけ。守りは弱まらない） |

World か Authenticated に Write があれば、他人が招待を書き換え・消せる（**高**。初期に戻すのは Production の変更なので、利用者の承認のあと）。
2026-10-21 に見えた「Read だけ」は、World の画面なら前提どおり。

**2026-10-22 の結果（利用者が Development と Production の両方で確認。変更・デプロイなし）:** `ShareInvite` は
World（`_world`）が Read だけ、Authenticated（`_icloud`）が Create だけ、Creator（`_creator`）が Write だけで、両方の環境で同じ。
上の表の前提どおりで、World・Authenticated に Write は無い（他人が招待を書き換え・消すことはできない）。**追加の対策は要らない。**
これは `ShareInvite` の権限の確認で、アプリ全体のセキュリティや通知の動作を確かめたものではない。

**任意の掃除（承認が要る操作）:** この版より前に発行された合言葉のレコード（`invite-` で始まるもの）は、
発行した端末に控えが無いので、アプリからは消せません。中身は共有のURLと期限で、期限はすべて切れています。
CloudKit Console から消すこともできますが、**既存データの削除にあたるので、Claudeからは行いません**。
消すかどうかは利用者が決めてください（消さなくても、アプリの動きは変わりません）。

---

## 9. 取り戻し（T-041）: 6つの場面

**前提:** 取り戻せるのは、合言葉を発行したか参加したことがあり、iCloudに置いてあった家計簿だけです。
iPhoneの中だけで使っていた家計簿は、アプリを消すと戻りません（アプリの入口と共有の画面に書いた）。
テストは `FutariKakeiboTests/SyncMergeTests.swift`（突き合わせ）と `RecoveryCandidateTests`（選ぶ一覧）。

| # | 場面 | どうなるか（コードから） | 自動テスト | 戻らないもの |
| --- | --- | --- | --- | --- |
| 1 | 招待した人（作った人）が削除して入れ直す | 入口の「以前の家計簿を取り戻す」（はじめの画面）で、自分のPrivate Databaseの家計簿を見つけて戻す。自分は「作った人」として戻る | `testAnEmptyPhoneTakesEverythingFromICloudAndPushesNothing`、`testTheMemberOnThisPhoneFollowsTheSideItCameBackFrom` | 消す前にまだ送れていなかった記録・レシート画像 |
| 2 | 招待された人（参加した人）が削除して入れ直す | 共有への参加はApple IDに残るので、Shared Databaseに家計簿が見える。「以前の家計簿を取り戻す」（はじめの画面）で戻る。参加する前に自分でも合言葉を発行していたら、2つ並ぶので選ぶ | 同上、`testTheMostRecentlyUsedHouseholdComesFirst`、`testATieGoesToTheSharedHousehold` | 同上 |
| 3 | 同じApple IDで機種変更 | iCloudバックアップ・クイックスタートで移したなら、手元のファイルごと移り、そのまま同期する。新しいiPhoneとして始めたなら 1・2 と同じ | 1・2 と同じ | iPhoneの中だけの家計簿は、バックアップから戻したときだけ戻る |
| 4 | 一時的にオフラインになってから戻る | 記録は手元に保存される。戻ったときの同期で、iCloudに無い・iCloudより新しい記録と削除印を送り直す | `testAfterBeingOfflineOurNewExpensesArePushedAndTheirsArrive`、`testALocalDeletionNotYetUploadedKeepsTheExpenseGoneAndIsSentAgain` | なし（送り直すまで相手には見えない） |
| 5 | ふたりが同時に同じ支出を直す | **後から直したほうが丸ごと残る**（各端末の時計の「直した時刻」で比べる）。先に直したほうの直しは消える。項目ごとに混ぜることはしない | `testWhenBothEditedTheNewerEditWinsAndTheOlderIsNotPushedBack`、`testWhenOurEditIsNewerItStaysAndIsPushed` | 負けたほうの直し（知らせは出ない） |
| 6 | 一方が消した支出が、古い端末から戻ってこない | 削除印は時刻を比べずに勝つ。古い端末がオフラインのあいだに直していても戻らない。iCloud側も、削除印のあるレコードは上書きしない（`expenseRecord`） | `testADeletionFromTheOtherPhoneBeatsAnOlderPhonesLaterEdit`、`testTheSameDeletionOnBothSidesKeepsTheLaterTimeAndIsNotResent` | なし |

**「復元できます」と言えないこと:**

- iPhoneの中だけで使っていた家計簿（合言葉を一度も発行・参加していない）は戻らない
- 5 の同時の直しでは、片方の直しが消える。iPhoneの時計が大きくずれていると、古い直しが勝つことがある
- 家計簿を作った人が共有をやめたあと、参加していた人は戻せない（その家計簿に入れなくなっている）

---

## 10. 実機での確認（利用者にお願いすること）

**このビルドで確かめていないことです。** Apple IDの違う2台（A: 家計簿を作る人、B: 参加する人）で行います。
**2026-10-22 から: 日常で使っている家計簿では、アプリの削除・入れ直し・共有をやめる操作をしない**（利用者の指示）。
いまの端末と本番のアプリで行えるのは **5・8・11・12・13**（11〜13 はテスト用の支出だけを使い、最後に消す）。
**1・3・4・7・9・10** は本番と分けたテスト用アプリで（`Docs/TEST_APP_PLAN.md`。まだ作っていない）、**2・6・14** は3つ目の Apple Account か協力者が要る。
対応は `Docs/RELEASE_PLAN.md` 付録A。

### 共有（T-040）

1. Aで合言葉を発行 → Bで入れる → Bが参加できる。Aの共有の画面に「合言葉が使われました」と「参加している人（2人）」が出る
2. 1 と**同じ合言葉**を、もう1台（Apple IDの違う3台目。無ければ飛ばす）で入れる → 「この合言葉はもう使われています」
3. Aで合言葉を2回続けて発行し、**1回目の**合言葉をBで入れる → 参加できない（「見つかりませんでした」）
4. 期限の切れた合言葉（発行から24時間後）を入れる → 「期限が切れています」
5. Bの共有の画面に「参加している人（2人）」と、名前（iCloudが教えてくれるとき）が出る
6. （3台目があれば）3人目が参加すると、AとBに「ふたりより多く参加しています」が赤字で出る。Aの「共有をやめる（全員が外れます）」
   → B と3人目の同期が止まり、Aの家計簿の記録は残る。Aで新しい合言葉を発行してBが入り直すと、記録がそろう。
   **Bが外れているあいだに足した支出も、入り直したあと消えずに残り、Aにも届く**
7. 家計簿を持っている端末で、別の家計簿の共有リンク（iCloudの招待）を開く → 「共有の招待を開きました」の確認が出る。
   「参加しない」で手元の家計簿がそのまま残る
8. 設定 →「データとプライバシー」に「共有するとiCloudへ」「合言葉は1回・1日だけ」が出て、「公開データベースは使いません」が無い

### 取り戻し（T-041）

9. （場面1）Aでアプリを削除 → 入れ直す → 「以前の家計簿を取り戻す」（はじめの画面） → 家計簿と支出が戻る。自分が「作った人」の名前になっている
10. （場面2）Bでアプリを削除 → 入れ直す → 「以前の家計簿を取り戻す」（はじめの画面） → 相手の家計簿に戻る。Bが前に自分で合言葉を発行したことがあれば、
    一覧が出て、相手の家計簿が先頭にある
11. （場面4）Bを機内モードにして支出を1件足し、1件消す → 機内モードを切ってアプリを開く → Aに足した1件が出て、消した1件が消える
12. （場面5）AとBで同じ支出を開き、ほぼ同時に違う金額で保存 → 30秒ほどで両方が、**後から保存したほうの金額**にそろう
13. （場面6）Bを機内モードにし、Aで支出を1件消す。Bでその支出を直して保存 → Bの機内モードを切る → その支出はBからも消える（戻ってこない）
14. （場面3、任意）同じApple IDの別のiPhoneに入れて「以前の家計簿を取り戻す」（はじめの画面） → 同じ家計簿に戻る

### レシート（T-042。2.0.0 / 2026.1019.16 以降のビルド）

15. ローソンのレシート（前に店名が「(肉海費祝動 11090袋」になったもの）を読み直す → 店名が「ローソン」系、種類が「その他」以外
16. PISOLA のレシート（前に合計が ¥659 になったもの）を読み直す → 合計 ¥7,257、店名が PISOLA
17. 外れたら、写真に加えて「読み取った文字を確認」の画面も撮って送ってください（読み取りが何を見たかが分かる）
18. 前に当たっていたレシート（スーパー・コンビニ・ガソリンスタンド）が、前と同じように当たる

---

## 11. 自動テスト（この監査で足したもの）

| テスト | 押さえていること |
| --- | --- |
| `SharingSafetyTests` | 共有の公開の権限が `.readWrite` のまま（変えるとパートナーが外れる）／使われた印があれば期限の内でも使えない／自分が作った印なら入り直せる・他人の印なら断る／印のレコード名が合言葉と重ならない／後片付けの判断（発行し直した・期限切れ・使われた・無くなった）／控えの無い古いファイルも読める・版は 4 のまま／ふたりより多い参加を数える／共有をやめる確認が「新しいリンク」を約束しない／リンクの招待で置き換わることを伝える／「データとプライバシー」が合言葉と家計のデータを分けて書く |
| `SyncMergeTests` | 削除印が古い端末の直しに勝つ／手元の削除印を送り直す／新しい直しが勝つ・古いほうを送り直さない／オフラインで足した記録を送り直す／空の端末はiCloudの内容をそのまま受け取る／同じIDが2つでも落ちない／収入も同じ |
| `RejoinSnapshotTests` | 同じ家計簿に入り直したとき、手元にしか無い記録・削除印・レシート画像の送信待ち・「自分」を残す／別の家計簿・iPhoneの中だけの家計簿からの参加は置き換える／合言葉の控えは引き継ぐ |
| `RecoveryCandidateTests` | 最近まで使われていた家計簿が先頭／同じ時刻なら共有された家計簿が先／最後の記録の時刻／戻った側で「自分」が決まる／入口の説明がiPhoneの中だけの家計簿を約束しない |

既存のテスト（OCRの `ZReceiptScoreboardTests` の下限を含む）は消しても緩めてもいません。
