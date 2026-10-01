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
