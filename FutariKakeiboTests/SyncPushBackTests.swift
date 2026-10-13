import XCTest
@testable import FutariKakeibo

/// 同期のときに「何を送り直すか」の選び方。
///
/// 以前はここが「全部」だった。支出が7件あれば取得の前に7往復し、
/// 相手の記録が画面に出るまで実機で10秒を超えていた。
final class SyncPushBackTests: XCTestCase {
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + seconds)
    }

    /// 両方に同じものがあり、時刻も同じなら送らない。ここが効かないと元に戻る。
    func testNothingIsPushedWhenBothSidesAgree() {
        let a = UUID(), b = UUID()
        let stale = AppStore.staleIDs(
            local: [(a, date(0)), (b, date(10))],
            remote: [(a, date(0)), (b, date(10))]
        )
        XCTAssertTrue(stale.isEmpty, "つじつまが合っているのに \(stale.count) 件送ろうとしている")
    }

    /// クラウドに無いものは送る。送信が失敗したまま残っている場合がこれ。
    func testSomethingMissingFromTheCloudIsPushed() {
        let a = UUID(), b = UUID()
        let stale = AppStore.staleIDs(
            local: [(a, date(0)), (b, date(10))],
            remote: [(a, date(0))]
        )
        XCTAssertEqual(stale, [b])
    }

    /// 手元のほうが新しいものは送る。機内モード中に直した場合がこれ。
    func testALocalEditNewerThanTheCloudIsPushed() {
        let a = UUID()
        let stale = AppStore.staleIDs(
            local: [(a, date(60))],
            remote: [(a, date(0))]
        )
        XCTAssertEqual(stale, [a])
    }

    /// クラウドのほうが新しいものは送らない。相手が直したものを押し戻さない。
    func testARemoteEditNewerThanOursIsNotPushedBack() {
        let a = UUID()
        let stale = AppStore.staleIDs(
            local: [(a, date(0))],
            remote: [(a, date(60))]
        )
        XCTAssertTrue(stale.isEmpty)
    }

    /// クラウドにしか無いものは、こちらから送るものではない。
    func testSomethingOnlyInTheCloudIsNotPushed() {
        let a = UUID(), b = UUID()
        let stale = AppStore.staleIDs(
            local: [(a, date(0))],
            remote: [(a, date(0)), (b, date(0))]
        )
        XCTAssertTrue(stale.isEmpty)
    }

    /// どちらも空でも落ちない。
    func testEmptySidesProduceNothing() {
        XCTAssertTrue(AppStore.staleIDs(local: [], remote: []).isEmpty)
    }
}

/// 「1回の通信に何件まとめるか」の区切り方。
///
/// 合言葉を発行するとき、支出と収入は1件ずつではなくまとめて送る。
/// 1件ずつ「取ってきて、保存する」をしていたころは、支出20件で40往復かかり、
/// 合言葉が画面に出るまでその往復ぶん待たされていた。
///
/// 区切りを1つ間違えると、送ったつもりのレコードが黙って落ちる。
/// 実機では「相手に出てこない1件」にしか見えないので、ここで確かめておく。
final class SyncBatchingTests: XCTestCase {
    /// 何件あっても、全部が1度ずつ、順番どおりに入っていること。
    func testChunkingKeepsEveryItemOnceAndInOrder() {
        let items = Array(0..<450)
        let chunks = CloudKitSyncService.chunked(items, size: 200)

        XCTAssertEqual(chunks.map(\.count), [200, 200, 50])
        XCTAssertEqual(chunks.flatMap { $0 }, items, "区切ったら中身が変わっている")
    }

    /// ちょうど割り切れるとき、空の束を作らないこと。
    /// 空の束をCloudKitへ送ると、意味のない往復が1回増える。
    func testAnExactMultipleDoesNotLeaveAnEmptyChunk() {
        let chunks = CloudKitSyncService.chunked(Array(0..<400), size: 200)

        XCTAssertEqual(chunks.count, 2)
        XCTAssertFalse(chunks.contains { $0.isEmpty }, "空の束ができている")
    }

    /// 送るものが無いときは、束も作らない。
    func testNothingProducesNoChunks() {
        XCTAssertTrue(CloudKitSyncService.chunked([Int](), size: 200).isEmpty)
    }

    /// 上限より少ないときは、1回で送る。
    func testFewerItemsThanTheLimitStayInOneChunk() {
        XCTAssertEqual(CloudKitSyncService.chunked([1, 2, 3], size: 200), [[1, 2, 3]])
    }

    /// 上限そのものがCloudKitの上限（400件前後）を超えていないこと。
    /// ここが大きすぎると、まとめた保存が丸ごと失敗する。
    func testTheDefaultLimitStaysUnderWhatCloudKitAccepts() {
        XCTAssertGreaterThan(CloudKitSyncService.batchSize, 0)
        XCTAssertLessThanOrEqual(CloudKitSyncService.batchSize, 400)
    }
}

/// 開いたままのアプリが、自分から相手の記録を取りに行く間隔。
///
/// 相手が保存したことを知らせてくれる仕組み（CKSubscription）はまだ無い。
/// 無いあいだは、前面にいるときだけ静かに取りに行くことで埋めている。
final class PeriodicRefreshTests: XCTestCase {
    /// **0秒や負の値だと、待たずに回り続けてCloudKitを叩き続ける。**
    /// 実機では電池が溶けるまで誰も気づかない壊れ方なので、ここで止める。
    /// 逆に長すぎると「開いたまま待っていても出てこない」という元の不満に戻る。
    func testTheIntervalHelpsWithoutHammeringTheCloud() {
        let seconds = AppStore.periodicRefreshInterval.components.seconds

        XCTAssertGreaterThanOrEqual(seconds, 10, "短すぎる。通信と電池を無駄に使う")
        XCTAssertLessThanOrEqual(seconds, 120, "長すぎる。待っている人には出てこないのと同じ")
    }
}

/// アプリを消して入れ直したとき、iCloudに残っている家計簿を見つけられるか。
///
/// **発行した側には戻り道が無かった。** 参加した側は合言葉をもう一度入れれば
/// 全部取り直せるが、発行した側は入れる合言葉を持たない（使い切りで消える）。
/// 残っていた手がかりは、ゾーンの名前だけだった。
final class HouseholdRecoveryTests: XCTestCase {
    /// 家計簿のゾーンだけを拾うこと。
    /// CloudKitは他の用途のゾーンも返すので、取り違えると別物を家計簿として開く。
    func testOnlyHouseholdZonesAreTakenAsCandidates() {
        let names = CloudKitSyncService.householdZoneNames(from: [
            "_defaultZone",
            "household-6a1f0c2e-0000-4000-8000-000000000001",
            "com.apple.coredata.cloudkit.zone",
            "household-6a1f0c2e-0000-4000-8000-000000000002",
            "receipts"
        ])

        XCTAssertEqual(names, [
            "household-6a1f0c2e-0000-4000-8000-000000000001",
            "household-6a1f0c2e-0000-4000-8000-000000000002"
        ])
    }

    /// 1つも無ければ空。初めてアプリを開いた人がこれにあたる。
    func testNothingToRecoverProducesNoCandidates() {
        XCTAssertTrue(CloudKitSyncService.householdZoneNames(from: ["_defaultZone"]).isEmpty)
        XCTAssertTrue(CloudKitSyncService.householdZoneNames(from: []).isEmpty)
    }

    /// 名前の付け方を変えたら、前に作った家計簿が見つからなくなる。
    /// **この接頭辞は prepareShare が作るゾーン名と同じでなければならない。**
    func testThePrefixStillMatchesTheNameWeWrite() {
        let service = CloudKitSyncService()
        let id = UUID()

        let zoneName = service.householdZoneName(for: id)

        XCTAssertTrue(zoneName.hasPrefix(CloudKitSyncService.householdZonePrefix))
        XCTAssertEqual(CloudKitSyncService.householdZoneNames(from: [zoneName]), [zoneName])
    }
}

/// 取り戻したあと、この端末の「自分」を誰にするか。
///
/// **実機で判明した取りこぼしの続き。** 最初はプライベート側（自分で作った家計簿）
/// しか探しておらず、参加した側の端末では必ず「見つかりませんでした」になった。
/// 共有側も探すようにしたので、こんどは**どちら側として戻ってきたか**で
/// 自分が入れ替わる。
final class RecoveredMemberTests: XCTestCase {
    private let owner = Member(displayName: "まさる", role: .owner)
    private let partner = Member(displayName: "つばさ", role: .partner)

    /// 自分で作った家計簿（プライベート側）から戻したなら、自分は発行した側。
    func testRecoveringOwnLedgerMakesYouTheOwner() {
        let me = AppStore.memberOnThisPhone(
            after: .privateDatabase,
            members: [owner, partner],
            ownerMemberID: owner.id
        )

        XCTAssertEqual(me, owner.id)
    }

    /// 相手から共有された家計簿（共有側）から戻したなら、自分は参加した側。
    /// **ここを取り違えると支出が相手の名前で記録されていく。**
    func testRecoveringASharedLedgerMakesYouThePartner() {
        let me = AppStore.memberOnThisPhone(
            after: .sharedDatabase,
            members: [owner, partner],
            ownerMemberID: owner.id
        )

        XCTAssertEqual(me, partner.id, "共有された家計簿なのに、持ち主を自分だと思っている")
    }

    /// 相手がまだ居ない家計簿を共有側から戻しても、誰も選べないまま落ちない。
    func testASharedLedgerWithOnlyTheOwnerStillPicksSomebody() {
        let me = AppStore.memberOnThisPhone(
            after: .sharedDatabase,
            members: [owner],
            ownerMemberID: owner.id
        )

        XCTAssertEqual(me, owner.id)
    }

    /// 人が1人も居なければ nil。ここで落とさない。
    func testNoMembersProducesNothing() {
        XCTAssertNil(AppStore.memberOnThisPhone(
            after: .privateDatabase,
            members: [],
            ownerMemberID: UUID()
        ))
    }
}
