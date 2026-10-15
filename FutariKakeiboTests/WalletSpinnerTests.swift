import XCTest
@testable import FutariKakeibo

/// 待ち時間のお財布（`WalletSpinner`）と、引っ張って更新の待ち方（`PullToRefresh`）。
final class WalletSpinnerTests: XCTestCase {

    // MARK: - 回り方

    /// 1回りの4分の1で90度。**正の向き（右回り）に、一定の速さで進むこと。**
    /// 利用者の指示は「正面を向いて右回転」（2026-10-13）。
    func testTheWalletTurnsClockwiseAtASteadySpeed() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let period = WalletSpinner.period

        XCTAssertEqual(WalletSpinner.angle(at: start).degrees, 0, accuracy: 0.001)
        XCTAssertEqual(WalletSpinner.angle(at: start.addingTimeInterval(period / 4)).degrees, 90, accuracy: 0.001)
        XCTAssertEqual(WalletSpinner.angle(at: start.addingTimeInterval(period / 2)).degrees, 180, accuracy: 0.001)
        XCTAssertEqual(WalletSpinner.angle(at: start.addingTimeInterval(period * 3 / 4)).degrees, 270, accuracy: 0.001)
    }

    /// 1回りしたら同じ角度に戻る。何時間開いていても角度が膨らまない。
    func testTheAngleRepeatsEveryTurn() {
        let period = WalletSpinner.period
        for turns in [1.0, 2.0, 1_000.0] {
            let date = Date(timeIntervalSinceReferenceDate: period * turns + period / 4)
            XCTAssertEqual(WalletSpinner.angle(at: date).degrees, 90, accuracy: 0.01)
        }
    }

    /// どの時刻でも0度以上360度未満。基準時刻（2001年）より前でも負にならない。
    func testTheAngleStaysWithinOneTurn() {
        for seconds in [-0.3, -1.1, -12.345, -1e-15, -1e-17, 0, 0.55, 987_654.321] {
            let degrees = WalletSpinner.angle(at: Date(timeIntervalSinceReferenceDate: seconds)).degrees
            XCTAssertGreaterThanOrEqual(degrees, 0, "\(seconds) 秒")
            XCTAssertLessThan(degrees, 360, "\(seconds) 秒")
        }
    }

    // MARK: - 引っ張って更新の待ち方

    /// 取得がすぐ終われば、すぐ戻って「終わった」と返す。
    func testRefreshEndsAsSoonAsTheWorkEnds() async {
        let clock = ContinuousClock()
        let start = clock.now

        let finished = await PullToRefresh.run(timeout: .seconds(10)) {}

        XCTAssertTrue(finished)
        XCTAssertLessThan(clock.now - start, .seconds(5), "取得が終わったのに上限まで待っている")
    }

    /// **通信が詰まっても回りっぱなしにしない。** 上限が来たら戻る。
    ///
    /// ただし**取得そのものは取り消さない。** 取り消すと CloudKit のやりとりが途中で切れ、
    /// 設定画面に「同期できませんでした」と出てしまう。裏で最後まで終わること。
    func testRefreshStopsWaitingAtTheLimitButLetsTheWorkFinish() async throws {
        let marker = await WorkMarker()
        let clock = ContinuousClock()
        let start = clock.now

        let finished = await PullToRefresh.run(timeout: .milliseconds(100)) {
            try? await Task.sleep(for: .milliseconds(800))
            await marker.markDone()
        }

        XCTAssertFalse(finished, "時間切れなのに「終わった」と返している")
        XCTAssertLessThan(clock.now - start, .milliseconds(700), "上限を過ぎても待ち続けている")
        let doneAtTimeout = await marker.isDone
        XCTAssertFalse(doneAtTimeout, "時間切れの時点では、まだ裏で動いているはず")

        try await Task.sleep(for: .seconds(2))
        let doneLater = await marker.isDone
        XCTAssertTrue(doneLater, "取り消されずに最後まで終わっていること")
    }

    /// 上限は、ふだんの取得（1〜3秒）より十分長く、回りっぱなしに見えるほど長くない。
    func testTheLimitIsLongEnoughForANormalRefresh() {
        let seconds = PullToRefresh.timeout.components.seconds

        XCTAssertGreaterThanOrEqual(seconds, 8, "短すぎる。ふだんの取得まで途中で打ち切って見える")
        XCTAssertLessThanOrEqual(seconds, 30, "長すぎる。詰まったときに回りっぱなしに見える")
    }
}

/// 裏で走らせた取得が最後まで終わったかを見るための印。
@MainActor
private final class WorkMarker {
    private(set) var isDone = false

    func markDone() {
        isDone = true
    }
}
