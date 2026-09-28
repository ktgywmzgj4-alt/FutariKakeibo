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
