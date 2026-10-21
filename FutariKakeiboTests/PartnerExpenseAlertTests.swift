import CloudKit
import UserNotifications
import XCTest
@testable import FutariKakeibo

/// 相手の支出の通知の決まり（`PartnerExpenseAlert`、T-044〜T-046）。
///
/// 通知が実際に出るか・押して開くか・アプリを閉じているときにどうなるかは、実機でしか確かめられない
/// （`Docs/NOTIFICATIONS.md` の「実機での確認」）。ここでは、何を知らせて何を知らせないかを確かめる。
@MainActor
final class PartnerExpenseAlertTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)
    private let me = "_me"
    private let partner = "_partner"
    private let payer = UUID()

    private var identity: PartnerExpenseAlert.Identity {
        PartnerExpenseAlert.Identity(placeholder: CKCurrentUserDefaultName, recordName: me)
    }

    private func expense(
        _ title: String = "スーパー",
        amount: Int = 1_234,
        createdAgo: TimeInterval = 60,
        recurringID: UUID? = nil,
        id: UUID = UUID()
    ) -> Expense {
        Expense(
            id: id,
            title: title,
            amount: amount,
            date: now,
            category: .groceries,
            paidByMemberID: payer,
            merchant: "テスト商店",
            recurringID: recurringID,
            createdAt: now.addingTimeInterval(-createdAgo),
            updatedAt: now.addingTimeInterval(-createdAgo)
        )
    }

    private func announce(
        _ merged: [Expense],
        creators: [UUID: String],
        knownBefore: Set<UUID> = [],
        alreadyAnnounced: Set<UUID> = [],
        identity: PartnerExpenseAlert.Identity? = nil
    ) -> [Expense] {
        PartnerExpenseAlert.expensesToAnnounce(
            knownBefore: knownBefore,
            merged: merged,
            creators: creators,
            identity: identity ?? self.identity,
            alreadyAnnounced: alreadyAnnounced,
            now: now
        )
    }

    // MARK: - 誰の登録か

    /// 相手が登録した新しい支出は知らせる。
    func testAPartnersNewExpenseIsAnnounced() {
        let theirs = expense()
        XCTAssertEqual(announce([theirs], creators: [theirs.id: partner]).map(\.id), [theirs.id])
    }

    /// 自分が登録した支出は知らせない（CloudKitが自分を決まった名前で返すときも、本当の名前で返すときも）。
    func testMyOwnExpenseIsNotAnnounced() {
        let byPlaceholder = expense()
        let byName = expense()
        let result = announce(
            [byPlaceholder, byName],
            creators: [byPlaceholder.id: CKCurrentUserDefaultName, byName.id: me]
        )
        XCTAssertTrue(result.isEmpty)
    }

    /// 自分の名前がまだ分からないときは、相手と決めつけない（自分の支出を相手のものとして知らせないため）。
    func testWhenMyNameIsUnknownNothingIsCalledThePartners() {
        let unknown = PartnerExpenseAlert.Identity(placeholder: CKCurrentUserDefaultName, recordName: nil)
        let theirs = expense()
        XCTAssertEqual(PartnerExpenseAlert.registrant(creator: partner, identity: unknown), .unknown)
        XCTAssertTrue(announce([theirs], creators: [theirs.id: partner], identity: unknown).isEmpty)
        XCTAssertEqual(PartnerExpenseAlert.registrant(creator: CKCurrentUserDefaultName, identity: unknown), .me)
    }

    /// 作成者の分からない支出（iCloudに無い・作成者が空）は知らせない。
    func testAnExpenseWithoutACreatorIsNotAnnounced() {
        let noCreator = expense()
        XCTAssertTrue(announce([noCreator], creators: [:]).isEmpty)
        XCTAssertEqual(PartnerExpenseAlert.registrant(creator: "", identity: identity), .unknown)
    }

    /// 支払った人（`paidByMemberID`）ではなく、登録した人で決める。
    /// 自分が登録した「相手が払った支出」は知らせない。
    func testThePayerDoesNotDecideWhoRegisteredIt() {
        let paidByPartner = expense()
        XCTAssertTrue(announce([paidByPartner], creators: [paidByPartner.id: me]).isEmpty)
    }

    // MARK: - 新しく届いたものだけ

    /// 同期の前から手元にあった支出は知らせない。家計簿に入った・取り戻した・入れ直したときに
    /// まとめて取り込んだ支出は、その時点で手元にあるので、次の同期で知らせることはない。
    func testExpensesAlreadyOnThisPhoneAreNotAnnounced() {
        let imported = expense()
        XCTAssertTrue(announce([imported], creators: [imported.id: partner], knownBefore: [imported.id]).isEmpty)
    }

    /// 相手が直した支出（手元にあったもの）は知らせない。消した支出は同期のあとに残らないので知らせない。
    func testEditsAndDeletionsAreNotAnnounced() {
        let edited = expense("直した")
        let deletedID = UUID()
        let result = announce(
            [edited],
            creators: [edited.id: partner, deletedID: partner],
            knownBefore: [edited.id, deletedID]
        )
        XCTAssertTrue(result.isEmpty)
    }

    /// 定期支出の自動計上は知らせない（ふたりの端末がそれぞれ同じ支出を作るため）。
    func testRecurringEntriesAreNotAnnounced() {
        let rent = expense("家賃", recurringID: UUID())
        XCTAssertTrue(announce([rent], creators: [rent.id: partner]).isEmpty)
    }

    /// 登録から3日を過ぎた支出は知らせない（相手の端末が長くオフラインだったときなど）。
    func testOldExpensesAreNotAnnounced() {
        let old = expense(createdAgo: PartnerExpenseAlert.freshness + 60)
        let recent = expense(createdAgo: PartnerExpenseAlert.freshness - 60)
        let result = announce([old, recent], creators: [old.id: partner, recent.id: partner])
        XCTAssertEqual(result.map(\.id), [recent.id])
    }

    // MARK: - 重ならない

    /// 一度知らせた支出は、もう知らせない。
    func testAnAlreadyAnnouncedExpenseIsNotAnnouncedAgain() {
        let theirs = expense()
        XCTAssertTrue(
            announce([theirs], creators: [theirs.id: partner], alreadyAnnounced: [theirs.id]).isEmpty
        )
    }

    /// 知らせた支出の控えは、新しいものを残して上限まで。同じIDは2回入れない。
    func testTheAnnouncedListKeepsTheNewestWithoutDuplicates() {
        let first = UUID()
        let second = UUID()
        XCTAssertEqual(PartnerExpenseAlert.remembering([first, first, second], in: []), [first, second])
        XCTAssertEqual(PartnerExpenseAlert.remembering([second], in: [first, second]), [first, second])

        let many = (0..<(PartnerExpenseAlert.rememberedLimit + 5)).map { _ in UUID() }
        let kept = PartnerExpenseAlert.remembering(many, in: [])
        XCTAssertEqual(kept.count, PartnerExpenseAlert.rememberedLimit)
        XCTAssertEqual(kept.last, many.last)
    }

    /// ふたりがほぼ同時に保存したら、それぞれの端末が相手の1件だけを知らせる。
    func testWhenBothSaveAtOnceEachPhoneAnnouncesOnlyTheOthers() {
        let mine = expense("わたし")
        let theirs = expense("あいて")
        // こちらの端末: 自分の支出は同期の前から手元にある。
        let here = announce([mine, theirs], creators: [mine.id: me, theirs.id: partner], knownBefore: [mine.id])
        XCTAssertEqual(here.map(\.id), [theirs.id])

        // 相手の端末: 立場が入れ替わる。
        let thereIdentity = PartnerExpenseAlert.Identity(placeholder: CKCurrentUserDefaultName, recordName: partner)
        let there = announce(
            [mine, theirs],
            creators: [mine.id: me, theirs.id: CKCurrentUserDefaultName],
            knownBefore: [theirs.id],
            identity: thereIdentity
        )
        XCTAssertEqual(there.map(\.id), [mine.id])
    }

    // MARK: - 通知の中身

    /// 1件なら、その支出を開く通知。**金額・店名・内容は出さない。**
    func testASingleNotificationOpensThatExpenseAndShowsNoDetails() throws {
        let theirs = expense("焼肉", amount: 8_765)
        let content = try XCTUnwrap(PartnerExpenseAlert.content(for: [theirs]))
        XCTAssertEqual(content.body, "パートナーが新しい支出を登録しました")
        XCTAssertEqual(content.expenseID, theirs.id)
        for secret in ["焼肉", "8765", "8,765", "テスト商店", "¥"] {
            XCTAssertFalse(content.body.contains(secret), secret)
        }
    }

    /// 1回の同期で何件届いても、通知は1つ。押すと履歴を開く（どれか1つには決めない）。
    func testManyArrivalsBecomeOneNotification() throws {
        let content = try XCTUnwrap(PartnerExpenseAlert.content(for: [expense(), expense(), expense()]))
        XCTAssertEqual(content.body, "パートナーが新しい支出を3件登録しました")
        XCTAssertNil(content.expenseID)
        XCTAssertNil(PartnerExpenseAlert.content(for: []))
    }

    /// 同じ支出の通知は同じ名前（重ならずに置き換わる）。
    func testTheSameExpenseAlwaysGetsTheSameIdentifier() {
        let theirs = expense()
        XCTAssertEqual(
            PartnerExpenseAlert.content(for: [theirs])?.identifier,
            PartnerExpenseAlert.content(for: [theirs])?.identifier
        )
    }

    /// 通知に入れた支出のIDを、押したときに読み戻せる。壊れた値なら開かない。
    func testTheTappedNotificationLeadsBackToTheExpense() {
        let id = UUID()
        XCTAssertEqual(PartnerExpenseAlert.expenseID(from: [PartnerExpenseAlert.expenseIDKey: id.uuidString]), id)
        XCTAssertNil(PartnerExpenseAlert.expenseID(from: [PartnerExpenseAlert.expenseIDKey: "壊れた値"]))
        XCTAssertNil(PartnerExpenseAlert.expenseID(from: [:]))
    }

    // MARK: - 許可と設定の文

    /// iPhoneの通知の許可の読み替え。分からない状態は「許可されていない」に倒す。
    func testPermissionStatesMapToWhatTheSettingsScreenShows() {
        XCTAssertEqual(NotificationPermission(.authorized), .allowed)
        XCTAssertEqual(NotificationPermission(.provisional), .allowed)
        XCTAssertEqual(NotificationPermission(.denied), .denied)
        XCTAssertEqual(NotificationPermission(.notDetermined), .notDetermined)
    }

    func testThePermissionLineTellsWhatToDo() {
        XCTAssertTrue(SettingsView.permissionText(.denied).contains("許可されていません"))
        XCTAssertTrue(SettingsView.permissionText(.notDetermined).contains("ONにすると確認が出ます"))
    }

    /// 設定の説明は、届かない場面を隠さない。同期が止まらないことと、金額を出さないことも書く。
    /// 閉じているあいだの通知は Apple が届くことを保証しないので、遅れる・届かない・終了させると届かない・
    /// 次に開いたときに追いつく、を書く（T-047）。
    func testTheSettingsNoteIsHonestAboutWhenNotificationsArrive() {
        let note = SettingsView.notificationNote
        XCTAssertTrue(note.contains("遅れたり届かなかったり"))
        XCTAssertTrue(note.contains("終了させると、次に開くまで届きません"))
        XCTAssertTrue(note.contains("次に開いたときにまとめて知らせます"))
        XCTAssertTrue(note.contains("同期は続きます"))
        XCTAssertTrue(note.contains("金額や店名は出しません"))
        XCTAssertTrue(note.contains("定期支出の自動計上は知らせません"))
    }

    /// 「データとプライバシー」にも、通知に金額や店名を出さないことを書く。
    func testThePrivacySummaryMentionsWhatNotificationsShow() {
        XCTAssertTrue(PrivacySummaryView.notificationDetail.contains("金額や店名は出しません"))
        XCTAssertTrue(PrivacySummaryView.notificationDetail.contains("ONにしたときだけ"))
    }

    /// 設定の保存先の名前を変えると、ONにしていた人の通知が黙ってOFFになる。変えない。
    /// （何も選んでいなければOFF。起動しただけで通知の許可を求めることはない）
    func testTheSettingKeyStaysTheSame() {
        XCTAssertEqual(AppStore.notifyPartnerExpensesKey, "notifyPartnerExpenses")
    }
}

/// アプリを閉じているあいだの通知（T-047）。CloudKitの購読をどうするかと、合図の見分け方。
///
/// 合図が実際に届くか・裏で起こされるかは実機でしか確かめられない（`Docs/NOTIFICATIONS.md` の5章）。
@MainActor
final class ExpenseSubscriptionPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func location(_ scope: CloudLocation.Scope) -> CloudLocation {
        CloudLocation(scope: scope, zoneName: "household", ownerName: "_owner", rootRecordName: "household")
    }

    private func plan(
        on: Bool,
        _ location: CloudLocation?,
        subscribed: CloudLocation.Scope? = nil,
        at: Date? = nil
    ) -> ExpenseSubscriptionPlan.Action {
        ExpenseSubscriptionPlan.action(
            notificationsOn: on,
            location: location,
            subscribedScope: subscribed,
            subscribedAt: at,
            now: now
        )
    }

    /// 通知がONで共有していれば、家計簿のある側に購読を置く（作った人はプライベート側、参加した人は共有側）。
    func testTurningOnSubscribesOnTheSideWhereTheLedgerLives() {
        XCTAssertEqual(plan(on: true, location(.privateDatabase)), .subscribe(.privateDatabase))
        XCTAssertEqual(plan(on: true, location(.sharedDatabase)), .subscribe(.sharedDatabase))
    }

    /// 通知をOFFにしたら外す（アプリを裏で起こさない）。置いていなければ何もしない。
    func testTurningOffUnsubscribes() {
        XCTAssertEqual(plan(on: false, location(.sharedDatabase), subscribed: .sharedDatabase, at: now), .unsubscribe(.sharedDatabase))
        XCTAssertEqual(plan(on: false, location(.sharedDatabase)), .keep)
    }

    /// 1日のあいだは置き直さない（電池と通信のため）。1日を過ぎたら置き直す（サーバーで消えていても戻る）。
    func testTheSubscriptionIsSentAgainAtMostOnceADay() {
        XCTAssertEqual(
            plan(on: true, location(.privateDatabase), subscribed: .privateDatabase, at: now.addingTimeInterval(-3_600)),
            .keep
        )
        XCTAssertEqual(
            plan(
                on: true,
                location(.privateDatabase),
                subscribed: .privateDatabase,
                at: now.addingTimeInterval(-ExpenseSubscriptionPlan.refreshInterval - 1)
            ),
            .subscribe(.privateDatabase)
        )
        // 置いた時刻が未来（端末の時計がずれた）なら、置き直す。
        XCTAssertEqual(
            plan(on: true, location(.privateDatabase), subscribed: .privateDatabase, at: now.addingTimeInterval(600)),
            .subscribe(.privateDatabase)
        )
    }

    /// 自分の家計簿から相手の家計簿に入ったら、古い側の購読を外して新しい側に置く。
    func testMovingToTheOtherSideMovesTheSubscription() {
        XCTAssertEqual(
            plan(on: true, location(.sharedDatabase), subscribed: .privateDatabase, at: now),
            .move(from: .privateDatabase, to: .sharedDatabase)
        )
    }

    /// 家計簿が見えないとき（起動の途中・共有していない）は、置いてある購読に触らない。
    func testWithoutAVisibleLedgerNothingIsTouched() {
        XCTAssertEqual(plan(on: true, nil, subscribed: .sharedDatabase, at: now), .keep)
        XCTAssertEqual(plan(on: true, nil), .keep)
    }

    /// 購読の名前は側ごとに1つ。作った側と参加した側で重ならない。
    func testEachSideHasItsOwnSubscription() {
        XCTAssertNotEqual(
            CloudKitSyncService.subscriptionID(for: .privateDatabase),
            CloudKitSyncService.subscriptionID(for: .sharedDatabase)
        )
    }

    /// CloudKitからの合図だけを同期のきっかけにする。ほかの通知では同期しない。
    func testOnlyCloudKitSignalsStartASync() {
        XCTAssertTrue(PartnerExpenseAlert.isCloudKitPush(["ck": ["cid": "iCloud.jp.aikawa.futarikakeibo"]]))
        XCTAssertFalse(PartnerExpenseAlert.isCloudKitPush(["aps": ["content-available": 1]]))
        XCTAssertFalse(PartnerExpenseAlert.isCloudKitPush([:]))
    }

    /// アプリが裏で動くのは、CloudKitの合図を受けるときだけ。定期の更新（fetch）は、
    /// 必要と確かめるまで入れない（2026-10-21 利用者の条件）。足すなら、このテストと一緒に理由を書く。
    func testTheAppOnlyAsksToWakeForRemoteNotifications() {
        let modes = Bundle(for: AppStore.self).object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        XCTAssertEqual(modes, ["remote-notification"])
        XCTAssertNil(Bundle(for: AppStore.self).object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers"))
    }
}
