import XCTest
@testable import FutariKakeibo

/// 手元とiCloudの記録の突き合わせ（`SyncMerge`）を、復元・オフライン・同時編集の場面で確かめる。
///
/// 2026-10-19 の監査（T-041）で、利用者が挙げた6つの場面のうち、CloudKitに触らずに確かめられる
/// ところをここに置く。実機が要る場面（入れ直し・機種変更）は `Docs/SHARING_SECURITY_AUDIT.md` の手順。
final class SyncMergeTests: XCTestCase {
    private let member = UUID()

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_760_000_000 + seconds)
    }

    private func expense(
        _ id: UUID = UUID(),
        title: String = "スーパー",
        amount: Int = 1_000,
        updated: TimeInterval = 0
    ) -> Expense {
        Expense(
            id: id,
            title: title,
            amount: amount,
            date: date(0),
            category: .groceries,
            paidByMemberID: member,
            createdAt: date(0),
            updatedAt: date(updated)
        )
    }

    // MARK: - 6 一方が削除した支出が、古い端末から復活しない

    /// 相手が消した支出を、こちらの古い端末がオフラインのあいだに直していても、戻ってこない。
    /// 削除印は時刻を比べずに勝つ（直したほうが新しくても）。
    func testADeletionFromTheOtherPhoneBeatsAnOlderPhonesLaterEdit() {
        let id = UUID()
        let result = SyncMerge.merge(
            local: [expense(id, title: "オフラインで直した", updated: 500)],
            localDeletions: [:],
            remote: [],
            remoteDeletions: [id: date(100)]
        )

        XCTAssertTrue(result.entries.isEmpty, "消された支出が戻ってきた")
        XCTAssertEqual(result.deletions[id], date(100))
        XCTAssertFalse(result.staleIDs.contains(id), "消された支出を送り直そうとしている")
        XCTAssertTrue(result.unsentDeletions.isEmpty, "iCloudにある削除印を送り直そうとしている")
    }

    /// こちらで消した支出が、iCloudにまだ残っていても戻ってこない。削除印は送り直す。
    func testALocalDeletionNotYetUploadedKeepsTheExpenseGoneAndIsSentAgain() {
        let id = UUID()
        let result = SyncMerge.merge(
            local: [],
            localDeletions: [id: date(200)],
            remote: [expense(id, updated: 50)],
            remoteDeletions: [:]
        )

        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertEqual(result.unsentDeletions, [id: date(200)])
    }

    /// 両方が同じ支出を消していたら、新しいほうの時刻を残し、送り直さない。
    func testTheSameDeletionOnBothSidesKeepsTheLaterTimeAndIsNotResent() {
        let id = UUID()
        let result = SyncMerge.merge(
            local: [Expense](),
            localDeletions: [id: date(300)],
            remote: [Expense](),
            remoteDeletions: [id: date(100)]
        )

        XCTAssertEqual(result.deletions[id], date(300))
        XCTAssertTrue(result.unsentDeletions.isEmpty)
    }

    // MARK: - 5 2人が同時に同じ支出を編集

    /// 後から直したほうが残る（端末の時計で比べる）。iCloudのほうが新しければ送り直さない。
    func testWhenBothEditedTheNewerEditWinsAndTheOlderIsNotPushedBack() {
        let id = UUID()
        let result = SyncMerge.merge(
            local: [expense(id, title: "わたしが直した", updated: 100)],
            localDeletions: [:],
            remote: [expense(id, title: "相手が直した", updated: 200)],
            remoteDeletions: [:]
        )

        XCTAssertEqual(result.entries.map(\.title), ["相手が直した"])
        XCTAssertTrue(result.staleIDs.isEmpty)
    }

    /// 手元のほうが新しければ手元を残し、送り直す（相手は次の同期でこちらの内容になる）。
    func testWhenOurEditIsNewerItStaysAndIsPushed() {
        let id = UUID()
        let result = SyncMerge.merge(
            local: [expense(id, title: "わたしが直した", updated: 300)],
            localDeletions: [:],
            remote: [expense(id, title: "相手が直した", updated: 200)],
            remoteDeletions: [:]
        )

        XCTAssertEqual(result.entries.map(\.title), ["わたしが直した"])
        XCTAssertEqual(result.staleIDs, [id])
    }

    // MARK: - 4 一時的にオフラインになってから復帰する

    /// オフラインのあいだに足した支出は残り、送り直しの対象になる。相手の新しい支出も入る。
    func testAfterBeingOfflineOurNewExpensesArePushedAndTheirsArrive() {
        let ours = expense(title: "電車で記録")
        let theirs = expense(title: "相手の記録")
        let result = SyncMerge.merge(
            local: [ours],
            localDeletions: [:],
            remote: [theirs],
            remoteDeletions: [:]
        )

        XCTAssertEqual(Set(result.entries.map(\.id)), [ours.id, theirs.id])
        XCTAssertEqual(result.staleIDs, [ours.id], "相手の支出まで送り直そうとしている")
    }

    // MARK: - 1〜3 入れ直し・機種変更（手元が空）

    /// 手元が空の端末（入れ直し・機種変更）では、iCloudの内容がそのまま入り、何も送り直さない。
    /// 削除印もiCloudのものを引き継ぐので、消した支出は戻らない。
    func testAnEmptyPhoneTakesEverythingFromICloudAndPushesNothing() {
        let kept = expense(title: "残っている支出")
        let deletedID = UUID()
        let result = SyncMerge.merge(
            local: [],
            localDeletions: [:],
            remote: [kept],
            remoteDeletions: [deletedID: date(50)]
        )

        XCTAssertEqual(result.entries.map(\.id), [kept.id])
        XCTAssertEqual(result.deletions[deletedID], date(50))
        XCTAssertTrue(result.staleIDs.isEmpty)
        XCTAssertTrue(result.unsentDeletions.isEmpty)
    }

    // MARK: - こわれにくさ

    /// 同じIDが2つあっても止まらない。新しいほうを残す。
    /// 以前は `Dictionary(uniqueKeysWithValues:)` で、重なるとアプリごと落ちていた。
    func testDuplicateIDsDoNotCrashAndTheNewerCopyIsKept() {
        let id = UUID()
        let result = SyncMerge.merge(
            local: [expense(id, title: "古い", updated: 10), expense(id, title: "新しい", updated: 20)],
            localDeletions: [:],
            remote: [expense(id, title: "iCloud", updated: 5), expense(id, title: "iCloud2", updated: 6)],
            remoteDeletions: [:]
        )

        XCTAssertEqual(result.entries.map(\.title), ["新しい"])
    }

    /// 収入も同じ決まりで突き合わせる。
    func testIncomesFollowTheSameRules() {
        let id = UUID()
        let income = Income(
            id: id,
            title: "給与",
            amount: 200_000,
            date: date(0),
            source: .salary,
            receivedByMemberID: member,
            createdAt: date(0),
            updatedAt: date(10)
        )
        let result = SyncMerge.merge(
            local: [income],
            localDeletions: [:],
            remote: [],
            remoteDeletions: [id: date(5)]
        )

        XCTAssertTrue(result.entries.isEmpty, "消された収入が戻ってきた")
    }
}

/// 入れ直したときに、iCloudに家計簿が2つ以上あったときの並び（T-041）。
@MainActor
final class RecoveryCandidateTests: XCTestCase {
    private func location(_ scope: CloudLocation.Scope, _ name: String) -> CloudLocation {
        CloudLocation(scope: scope, zoneName: name, ownerName: "owner", rootRecordName: name)
    }

    private func candidate(_ scope: CloudLocation.Scope, _ name: String, last: TimeInterval) -> RecoveryCandidate {
        RecoveryCandidate(
            location: location(scope, name),
            householdName: name,
            memberNames: ["そら", "つばさ"],
            expenseCount: 1,
            incomeCount: 0,
            lastActivity: Date(timeIntervalSince1970: last)
        )
    }

    /// いちばん最近まで使われていた家計簿が先頭。参加する前に作って放ってある家計簿は後ろ。
    /// 以前は自分で作ったほうを必ず選んでいたので、古いほうに戻っていた。
    func testTheMostRecentlyUsedHouseholdComesFirst() {
        let old = candidate(.privateDatabase, "household-old", last: 1_000)
        let shared = candidate(.sharedDatabase, "household-shared", last: 9_000)

        XCTAssertEqual(RecoveryCandidate.ranked([old, shared]).map(\.householdName), ["household-shared", "household-old"])
    }

    /// 同じ時刻なら、相手から共有された家計簿（ふたりで使っているほう）を先に。
    func testATieGoesToTheSharedHousehold() {
        let own = candidate(.privateDatabase, "own", last: 5_000)
        let shared = candidate(.sharedDatabase, "shared", last: 5_000)

        XCTAssertEqual(RecoveryCandidate.ranked([own, shared]).first?.householdName, "shared")
    }

    /// 要約の「最後の記録」は、家計簿の設定・支出・収入のうちいちばん新しい更新時刻。
    func testTheLastActivityIsTheNewestOfHouseholdExpensesAndIncomes() {
        let owner = Member(displayName: "そら", role: .owner)
        var household = Household(monthlyBudget: 100_000, members: [owner], ownerMemberID: owner.id)
        household.updatedAt = Date(timeIntervalSince1970: 100)
        let expense = Expense(
            title: "外食",
            amount: 3_000,
            category: .dining,
            paidByMemberID: owner.id,
            createdAt: Date(timeIntervalSince1970: 50),
            updatedAt: Date(timeIntervalSince1970: 700)
        )
        let summary = RecoveryCandidate(
            location: location(.privateDatabase, "z"),
            household: household,
            expenses: [expense],
            incomes: []
        )

        XCTAssertEqual(summary.lastActivity, Date(timeIntervalSince1970: 700))
        XCTAssertEqual(summary.expenseCount, 1)
        XCTAssertEqual(summary.memberNames, ["そら"])
        XCTAssertTrue(summary.isOwnHousehold)
    }

    /// 戻ったあとの「自分」は、どちら側から戻ったかで決まる（取り違えると支出が相手の名前になる）。
    func testTheMemberOnThisPhoneFollowsTheSideItCameBackFrom() {
        let owner = Member(displayName: "そら", role: .owner)
        let partner = Member(displayName: "つばさ", role: .partner)

        XCTAssertEqual(
            AppStore.memberOnThisPhone(after: .privateDatabase, members: [owner, partner], ownerMemberID: owner.id),
            owner.id
        )
        XCTAssertEqual(
            AppStore.memberOnThisPhone(after: .sharedDatabase, members: [owner, partner], ownerMemberID: owner.id),
            partner.id
        )
    }

    /// 戻せない家計簿に「戻せます」と言わない。入口の説明は、iCloudに置いてあった家計簿だけが戻ると書く。
    func testTheRecoveryHintDoesNotPromiseToRestoreAPhoneOnlyLedger() {
        XCTAssertTrue(OnboardingView.recoveryHint.contains("iCloudに置いてあった"))
        XCTAssertTrue(OnboardingView.recoveryHint.contains("戻せません"))
        XCTAssertFalse(OnboardingView.recoveryHint.contains("このiPhoneを前にも使っていたなら"))
    }
}

/// 家計簿に入ったあとの手元（`AppStore.snapshotAfterJoining`）。
///
/// 同じ家計簿に入り直したとき（共有をやめられて外れたあと・同じ合言葉の家計簿にもう一度入ったとき）、
/// 手元にしか無い記録を消さない。2026-10-19 の監査で、置き換えて消していたのを直した。
@MainActor
final class RejoinSnapshotTests: XCTestCase {
    private let owner = Member(displayName: "そら", role: .owner)
    private let partner = Member(displayName: "つばさ", role: .partner)

    private func location(_ zone: String) -> CloudLocation {
        CloudLocation(scope: .sharedDatabase, zoneName: zone, ownerName: "_owner", rootRecordName: zone)
    }

    private func household(at location: CloudLocation?) -> Household {
        var household = Household(monthlyBudget: 100_000, members: [owner, partner], ownerMemberID: owner.id)
        household.cloudLocation = location
        return household
    }

    private func expense(_ title: String, updated: TimeInterval = 0, id: UUID = UUID()) -> Expense {
        Expense(
            id: id,
            title: title,
            amount: 1_000,
            date: Date(timeIntervalSince1970: 1_760_000_000),
            category: .groceries,
            paidByMemberID: partner.id,
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_760_000_000 + updated)
        )
    }

    private func cloud(expenses: [Expense], deletions: [UUID: Date] = [:]) -> CloudKitSyncService.CloudSnapshot {
        CloudKitSyncService.CloudSnapshot(
            household: household(at: nil),
            expenses: expenses,
            incomes: [],
            deletedExpenseIDs: deletions,
            deletedIncomeIDs: [:]
        )
    }

    /// 外れていたあいだに足した記録・消した記録は、入り直しても残る（次の同期で送る）。
    func testRejoiningTheSameHouseholdKeepsWhatIsOnlyOnThisPhone() {
        let here = location("household-a")
        let onlyHere = expense("外れていたあいだに足した")
        let sharedID = UUID()
        let deletedHere = UUID()
        let theirs = expense("相手の記録")
        let pendingImage = UUID()
        let current = AppSnapshot(
            household: household(at: here),
            selectedMemberID: partner.id,
            expenses: [onlyHere, expense("古い", updated: 10, id: sharedID)],
            deletedExpenseIDs: [deletedHere: Date(timeIntervalSince1970: 1_760_000_500)],
            pendingReceiptImageIDs: [pendingImage]
        )

        let result = AppStore.snapshotAfterJoining(
            current: current,
            cloud: cloud(expenses: [expense("新しい", updated: 20, id: sharedID), theirs, expense("消した", id: deletedHere)]),
            at: here
        )

        XCTAssertEqual(Set(result.expenses.map(\.title)), ["外れていたあいだに足した", "新しい", "相手の記録"])
        XCTAssertNotNil(result.deletedExpenseIDs[deletedHere], "手元で消した印がなくなった")
        XCTAssertEqual(result.selectedMemberID, partner.id)
        XCTAssertEqual(result.pendingReceiptImageIDs, [pendingImage], "送信待ちのレシート画像を忘れた")
        XCTAssertEqual(result.household?.cloudLocation, here)
    }

    /// 別の家計簿に入ったときは置き換える（参加する前に画面で伝えている）。合言葉の控えは引き継ぐ。
    func testJoiningAnotherHouseholdReplacesTheLedgerButKeepsTheIssuedInvites() {
        var current = AppSnapshot(
            household: household(at: location("household-old")),
            selectedMemberID: owner.id,
            expenses: [expense("前の家計簿の記録")],
            pendingReceiptImageIDs: [UUID()]
        )
        current.issuedInvites = [IssuedInvite(code: "ABCD2345", expiresAt: Date(timeIntervalSince1970: 1_760_000_000))]
        let joined = location("household-new")

        let result = AppStore.snapshotAfterJoining(
            current: current,
            cloud: cloud(expenses: [expense("相手の記録")]),
            at: joined
        )

        XCTAssertEqual(result.expenses.map(\.title), ["相手の記録"])
        XCTAssertTrue(result.pendingReceiptImageIDs.isEmpty)
        XCTAssertEqual(result.selectedMemberID, partner.id, "参加した側は「相手」の名前で記録する")
        XCTAssertEqual(result.issuedInvites.map(\.code), ["ABCD2345"])
    }

    /// iPhoneの中だけで使っていた人が参加したときも、置き換え（これまでと同じ）。
    func testJoiningFromAPhoneOnlyLedgerReplacesIt() {
        let current = AppSnapshot(household: household(at: nil), expenses: [expense("iPhoneの中だけ")])
        let result = AppStore.snapshotAfterJoining(
            current: current,
            cloud: cloud(expenses: []),
            at: location("household-new")
        )
        XCTAssertTrue(result.expenses.isEmpty)
    }
}

/// 共有の形を移す準備（T-048）。入り直しで手元を消さないことと、移す前の条件。
@MainActor
final class SharingMigrationPreparationTests: XCTestCase {
    private let owner = Member(displayName: "そら", role: .owner)
    private let partner = Member(displayName: "つばさ", role: .partner)
    private let householdID = UUID()

    private func location(_ zone: String, _ scope: CloudLocation.Scope = .sharedDatabase) -> CloudLocation {
        CloudLocation(scope: scope, zoneName: zone, ownerName: "_owner", rootRecordName: zone)
    }

    private func household(at location: CloudLocation?, name: String = "ふたりの家計", updated: TimeInterval) -> Household {
        Household(
            id: householdID,
            name: name,
            monthlyBudget: 100_000,
            members: [owner, partner],
            ownerMemberID: owner.id,
            cloudLocation: location,
            updatedAt: Date(timeIntervalSince1970: 1_760_000_000 + updated)
        )
    }

    private func expense(_ title: String) -> Expense {
        Expense(
            title: title,
            amount: 500,
            date: Date(timeIntervalSince1970: 1_760_000_000),
            category: .groceries,
            paidByMemberID: partner.id,
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
    }

    private func cloud(_ household: Household, expenses: [Expense] = []) -> CloudKitSyncService.CloudSnapshot {
        CloudKitSyncService.CloudSnapshot(
            household: household,
            expenses: expenses,
            incomes: [],
            deletedExpenseIDs: [:],
            deletedIncomeIDs: [:]
        )
    }

    /// 家計簿を別の場所へ写して共有し直しても、IDが同じなら同じ家計簿。手元にしか無い記録は消さない。
    func testRejoiningACopyOfTheSameHouseholdElsewhereKeepsLocalRecords() {
        let old = location("household-old")
        let moved = location("household-new")
        let onlyHere = expense("外れていたあいだに足した")
        let current = AppSnapshot(household: household(at: old, updated: 0), expenses: [onlyHere])

        let result = AppStore.snapshotAfterJoining(
            current: current,
            cloud: cloud(household(at: nil, updated: 0), expenses: [expense("iCloudの記録")]),
            at: moved
        )

        XCTAssertTrue(result.expenses.contains { $0.id == onlyHere.id }, "手元にしか無い記録が消えた")
        XCTAssertEqual(result.household?.cloudLocation, moved, "新しい場所に付け替わっていない")
    }

    /// 別々に作った家計簿（IDが違う）は、場所が違えば置き換える（これまでどおり）。
    func testADifferentHouseholdIsNotTreatedAsTheSame() {
        let other = Household(monthlyBudget: 1, members: [owner, partner], ownerMemberID: owner.id)
        XCTAssertFalse(AppStore.isSameHousehold(other, as: household(at: nil, updated: 0), at: location("z")))
        XCTAssertFalse(AppStore.isSameHousehold(nil, as: household(at: nil, updated: 0), at: location("z")))
        XCTAssertTrue(AppStore.isSameHousehold(household(at: nil, updated: 0), as: household(at: nil, updated: 9), at: location("z")))
    }

    /// 外れていたあいだに変えた設定（手元のほうが新しい）は残す。iCloudのほうが新しければそちら。
    func testRejoiningKeepsTheNewerSettings() {
        let here = location("household-a")
        let newerLocal = AppSnapshot(household: household(at: here, name: "手元で変えた名前", updated: 200))
        let keptLocal = AppStore.snapshotAfterJoining(
            current: newerLocal,
            cloud: cloud(household(at: nil, name: "iCloudの名前", updated: 100)),
            at: here
        )
        XCTAssertEqual(keptLocal.household?.name, "手元で変えた名前")
        XCTAssertEqual(keptLocal.household?.cloudLocation, here)

        let olderLocal = AppSnapshot(household: household(at: here, name: "手元の古い名前", updated: 100))
        let tookCloud = AppStore.snapshotAfterJoining(
            current: olderLocal,
            cloud: cloud(household(at: nil, name: "iCloudの新しい名前", updated: 200)),
            at: here
        )
        XCTAssertEqual(tookCloud.household?.name, "iCloudの新しい名前")
    }

    // MARK: - 移す前の条件（ShareMigrationReadiness）

    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    func testOnlyTheOwnersPhoneRightAfterASyncWithNothingPendingIsReady() {
        let blockers = ShareMigrationReadiness.blockers(
            location: location("z", .privateDatabase),
            lastSyncedAt: now.addingTimeInterval(-60),
            pendingReceiptImageCount: 0,
            now: now
        )
        XCTAssertTrue(blockers.isEmpty)
    }

    func testEachReasonToWaitIsReported() {
        XCTAssertEqual(
            ShareMigrationReadiness.blockers(location: nil, lastSyncedAt: now, pendingReceiptImageCount: 0, now: now),
            [.notShared]
        )
        XCTAssertEqual(
            ShareMigrationReadiness.blockers(
                location: location("z", .sharedDatabase),
                lastSyncedAt: now.addingTimeInterval(-ShareMigrationReadiness.recentSyncWindow - 1),
                pendingReceiptImageCount: 2,
                now: now
            ),
            [.notOwner, .notRecentlySynced, .pendingReceiptImages(2)]
        )
        XCTAssertEqual(
            ShareMigrationReadiness.blockers(
                location: location("z", .privateDatabase),
                lastSyncedAt: nil,
                pendingReceiptImageCount: 0,
                now: now
            ),
            [.notRecentlySynced]
        )
    }

    /// 端末の時計が先に進んでいて「同期したのが未来」に見えるときも、済んだとはみなさない。
    func testASyncTimeInTheFutureDoesNotCount() {
        XCTAssertEqual(
            ShareMigrationReadiness.blockers(
                location: location("z", .privateDatabase),
                lastSyncedAt: now.addingTimeInterval(60),
                pendingReceiptImageCount: 0,
                now: now
            ),
            [.notRecentlySynced]
        )
    }
}
