import CloudKit
import XCTest
@testable import FutariKakeibo

/// 合言葉と共有の安全（2026-10-19 の監査、T-040）。
///
/// この共有は「URLを知っている人なら誰でも参加できる」形（`publicPermission = .readWrite`）。
/// 守りは合言葉の側にある: 1回だけ・1日で切れる・使ったら消す。ここが崩れると、
/// 合言葉が漏れたときに知らない人が家計簿を読み書きできる。CloudKitに触らない部分をここで確かめる。
@MainActor
final class SharingSafetyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    // MARK: - 共有の権限

    /// 共有の公開の権限は「URLを知っている人なら読み書きできる」のまま。
    /// `.none` にすると、Appleの説明どおり公開の参加者が全員外れ、パートナーが家計簿に入れなくなる。
    /// 変えるなら、先に移行の手順（`Docs/SHARING_SECURITY_AUDIT.md`）を用意してからこのテストを直す。
    func testTheSharePermissionStaysSoTheCurrentPartnerIsNotRemoved() {
        XCTAssertEqual(CloudKitSyncService.sharePublicPermission, .readWrite)
    }

    // MARK: - 合言葉は1回だけ

    /// 使われた印があれば、期限の内でも使えない。
    /// 以前は参加した側が合言葉を消そうとして失敗し（消せるのは発行した人だけ）、1日のあいだ誰でも使えた。
    func testAUsedInviteCannotBeUsedEvenBeforeItExpires() {
        XCTAssertEqual(
            ShareInvite.state(exists: true, expiresAt: now.addingTimeInterval(3_600), isUsed: true, now: now),
            .used
        )
    }

    func testAFreshInviteIsActive() {
        XCTAssertEqual(
            ShareInvite.state(exists: true, expiresAt: now.addingTimeInterval(3_600), isUsed: false, now: now),
            .active
        )
    }

    /// 期限ちょうどは、もう使えない。
    func testAnInviteAtItsExpiryIsExpired() {
        XCTAssertEqual(ShareInvite.state(exists: true, expiresAt: now, isUsed: false, now: now), .expired)
        XCTAssertEqual(ShareInvite.state(exists: true, expiresAt: nil, isUsed: false, now: now), .expired)
    }

    func testAMissingInviteIsGone() {
        XCTAssertEqual(ShareInvite.state(exists: false, expiresAt: nil, isUsed: false, now: now), .gone)
    }

    /// 「使われた印」のレコード名は、合言葉のレコード名と重ならない（合言葉の文字に「-」は無い）。
    func testTheUsedMarkNeverCollidesWithAnInviteRecord() {
        let code = ShareInvite.makeCode()
        XCTAssertFalse(ShareInvite.alphabet.contains("-"))
        XCTAssertEqual(CloudKitSyncService.inviteUsedRecordName(for: code), "invite-used-\(code)")
        XCTAssertNotEqual(CloudKitSyncService.inviteUsedRecordName(for: code), "invite-\(code)")
    }

    /// 印を作ったのが自分なら、参加しかけて通信が切れただけなので、もう一度進める。
    /// 他の人が作った印なら、その合言葉はもう使えない。作った人が分からなければ、使えないほうに倒す。
    func testOnlyTheUsedMarkMadeByThisPersonLetsThemRetry() {
        let mine = CKRecord.ID(recordName: CKCurrentUserDefaultName)
        XCTAssertTrue(CloudKitSyncService.isCurrentUser(mine, currentUserRecordName: nil))
        XCTAssertTrue(
            CloudKitSyncService.isCurrentUser(CKRecord.ID(recordName: "_me"), currentUserRecordName: "_me")
        )
        XCTAssertFalse(
            CloudKitSyncService.isCurrentUser(CKRecord.ID(recordName: "_other"), currentUserRecordName: "_me")
        )
        XCTAssertFalse(
            CloudKitSyncService.isCurrentUser(CKRecord.ID(recordName: "_other"), currentUserRecordName: nil)
        )
        XCTAssertFalse(CloudKitSyncService.isCurrentUser(nil, currentUserRecordName: "_me"))
    }

    /// 使われた合言葉を入れた人には、どうすればよいかを伝える。
    func testTheUsedMessageTellsThePersonWhatToDo() {
        let message = AppStore.inviteFailureMessage(for: CloudKitSyncService.SyncError.inviteAlreadyUsed)
        XCTAssertTrue(message.contains("もう使われています"))
        XCTAssertTrue(message.contains("新しい合言葉"))
    }

    // MARK: - 発行した合言葉の後片付け

    /// 発行し直して要らなくなった合言葉は、見に行かずに消す。
    func testASupersededInviteIsWithdrawnWithoutAsking() {
        let old = IssuedInvite(code: "AAAAAAAA", expiresAt: now.addingTimeInterval(100))
        XCTAssertFalse(IssuedInvite.needsRemoteCheck(old, isLatest: false, now: now))
        XCTAssertEqual(IssuedInvite.disposition(old, isLatest: false, remoteState: nil, now: now), .withdraw)
    }

    /// 期限の切れた合言葉は、見に行かずに消す（共有のURLが入っているので残さない）。
    func testAnExpiredInviteIsWithdrawnWithoutAsking() {
        let expired = IssuedInvite(code: "BBBBBBBB", expiresAt: now.addingTimeInterval(-1))
        XCTAssertFalse(IssuedInvite.needsRemoteCheck(expired, isLatest: true, now: now))
        XCTAssertEqual(IssuedInvite.disposition(expired, isLatest: true, remoteState: nil, now: now), .withdraw)
    }

    /// 画面に出している合言葉は、使われるまで残す。見に行けなかったときも残す（次の同期で見る）。
    func testTheLatestInviteStaysUntilItIsUsed() {
        let latest = IssuedInvite(code: "CCCCCCCC", expiresAt: now.addingTimeInterval(3_600))
        XCTAssertTrue(IssuedInvite.needsRemoteCheck(latest, isLatest: true, now: now))
        XCTAssertEqual(IssuedInvite.disposition(latest, isLatest: true, remoteState: .active, now: now), .keep)
        XCTAssertEqual(IssuedInvite.disposition(latest, isLatest: true, remoteState: nil, now: now), .keep)
    }

    func testAUsedInviteIsWithdrawnAndAGoneOneIsForgotten() {
        let latest = IssuedInvite(code: "DDDDDDDD", expiresAt: now.addingTimeInterval(3_600))
        XCTAssertEqual(IssuedInvite.disposition(latest, isLatest: true, remoteState: .used, now: now), .withdraw)
        XCTAssertEqual(IssuedInvite.disposition(latest, isLatest: true, remoteState: .gone, now: now), .forget)
    }

    func testTheLatestInviteIsTheOneThatExpiresLast() {
        let first = IssuedInvite(code: "EEEEEEEE", expiresAt: now)
        let second = IssuedInvite(code: "FFFFFFFF", expiresAt: now.addingTimeInterval(60))
        XCTAssertEqual(IssuedInvite.latest(in: [second, first])?.code, "FFFFFFFF")
        XCTAssertNil(IssuedInvite.latest(in: []))
    }

    // MARK: - 発行した合言葉の控え（端末に残す）

    /// 控えの無い前の版のファイルも、そのまま読める。
    func testOldSnapshotsWithoutIssuedInvitesStillLoad() throws {
        let json = #"{"schemaVersion":4,"expenses":[],"incomes":[]}"#
        let snapshot = try JSONDecoder().decode(AppSnapshot.self, from: Data(json.utf8))
        XCTAssertTrue(snapshot.issuedInvites.isEmpty)
    }

    func testIssuedInvitesSurviveARoundTrip() throws {
        var snapshot = AppSnapshot()
        snapshot.issuedInvites = [IssuedInvite(code: "ABCD2345", expiresAt: now)]
        let decoded = try JSONDecoder().decode(AppSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.issuedInvites, snapshot.issuedInvites)
    }

    /// 控えを足しても、ファイルの版は上げない。古い版のアプリは新しい版のファイルを読まずに止まるので、
    /// TestFlightで前のビルドに戻したときに家計簿が開けなくなる。
    func testTheSnapshotVersionStaysSoOlderBuildsCanStillOpenIt() {
        XCTAssertEqual(AppSnapshot.currentSchemaVersion, 4)
    }

    // MARK: - 共有に参加している人

    private func member(owner: Bool = false, me: Bool = false, accepted: Bool = true, name: String? = nil)
        -> CloudKitSyncService.ShareMember {
        CloudKitSyncService.ShareMember(isOwner: owner, isCurrentUser: me, hasAccepted: accepted, name: name)
    }

    func testTwoPeopleAreExpected() {
        XCTAssertEqual(CloudKitSyncService.strangerCount(in: [member(owner: true), member()]), 0)
        XCTAssertEqual(CloudKitSyncService.strangerCount(in: [member(owner: true)]), 0)
    }

    /// ふたりより多く参加していれば知らせる。合言葉かリンクが漏れたときに起きる。
    func testAThirdPersonIsFlagged() {
        XCTAssertEqual(
            CloudKitSyncService.strangerCount(in: [member(owner: true), member(), member()]),
            1
        )
    }

    /// 参加していない（招待中・外された）人は数えない。
    func testPeopleWhoHaveNotJoinedAreNotCounted() {
        XCTAssertEqual(
            CloudKitSyncService.strangerCount(in: [member(owner: true), member(), member(accepted: false)]),
            0
        )
    }

    func testMemberLinesSayWhoMadeItAndWhoYouAre() {
        XCTAssertEqual(SharingView.memberLine(member(owner: true, me: true, name: "そら")), "・そら（作った人・あなた）")
        XCTAssertEqual(SharingView.memberLine(member(name: "つばさ")), "・つばさ")
        XCTAssertTrue(SharingView.memberLine(member()).contains("名前は表示されません"))
    }

    /// 共有をやめても、始め直せば共有のリンクは前と同じ（Appleの `CKShare.url` の説明）。
    /// 「やめれば前のリンクでは入れない」と約束しない。パートナーも外れることは必ず伝える。
    func testStoppingTheShareDoesNotPromiseANewLink() {
        let message = SharingView.stopSharingMessage
        XCTAssertTrue(message.contains("パートナーも含めて"))
        XCTAssertTrue(message.contains("記録は消えません"))
        XCTAssertTrue(message.contains("前と同じ"))
        XCTAssertFalse(message.contains("新しいURL"))
        XCTAssertFalse(message.contains("入れなくなります。パートナーには"))
    }

    // MARK: - 共有のリンクから届いた招待

    /// すでに家計簿がある人に、置き換わることと、知らない人のリンクに参加しないことを伝える。
    func testTheInvitationWarnsThatTheLedgerWillBeReplaced() {
        let message = RootView.invitationMessage(ownerName: "そら")
        XCTAssertTrue(message.contains("そらさんの家計簿"))
        XCTAssertTrue(message.contains("置き換わり"))
        XCTAssertTrue(message.contains("知らない人"))
        XCTAssertTrue(RootView.invitationMessage(ownerName: nil).hasPrefix("この家計簿"))
    }

    // MARK: - 「データとプライバシー」の説明

    /// 合言葉は公開データベースに置いている。「公開データベースは使いません」と書かない。
    /// 家計のデータ本体と合言葉を分けて書く。
    func testThePrivacySummaryTellsWhereTheInviteAndTheLedgerLive() {
        let invite = PrivacySummaryView.inviteDetail
        XCTAssertTrue(invite.contains("公開データベース"))
        XCTAssertTrue(invite.contains("家計のデータは置きません"))
        XCTAssertTrue(invite.contains("1回"))
        XCTAssertTrue(invite.contains("1日"))

        let ledger = PrivacySummaryView.householdSharingDetail
        XCTAssertTrue(ledger.contains("公開データベースには置きません"))
        for text in [invite, ledger] {
            XCTAssertFalse(text.contains("公開データベースは使いません"), text)
        }
    }
}
