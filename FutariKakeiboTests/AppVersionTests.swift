import XCTest
@testable import FutariKakeibo

/// 設定画面に出る版の行。
///
/// **この種の不具合を二度出さないための押さえ。** 以前は
/// `Text("Version 0.1.0 (1)")` と文字列で書いてあったので、
/// どのビルドを入れても最初のビルド番号が出ていた。
/// 利用者からは「自動アップデートで最初の版に戻る」と見えていた（2026-10-13）。
final class AppVersionTests: XCTestCase {

    /// ふだんの形。**ビルド番号まで出ること。**
    /// 不具合の報告を受けたとき、配信のどれかをここで見分ける。
    func testTheLineShowsBothTheVersionAndTheBuild() {
        let appVersion = AppVersion(version: "0.2.0", build: "2026.1013.2229")

        XCTAssertEqual(appVersion.displayText, "Version 0.2.0 (2026.1013.2229)")
    }

    /// **配信ごとにビルド番号が変われば、行も変わること。**
    /// 決め打ちに戻ると、この2つが同じ文字列になって落ちる。
    func testTwoDifferentBuildsDoNotShowTheSameLine() {
        let older = AppVersion(version: "0.2.0", build: "2026.1004.0900")
        let newer = AppVersion(version: "0.2.0", build: "2026.1013.2229")

        XCTAssertNotEqual(older.displayText, newer.displayText)
    }

    /// 版だけ読めたとき。空の括弧は出さない。
    func testAMissingBuildNumberDoesNotLeaveEmptyBrackets() {
        let appVersion = AppVersion(version: "0.2.0", build: "")

        XCTAssertEqual(appVersion.displayText, "Version 0.2.0")
    }

    /// ビルド番号だけ読めたとき。
    func testOnlyTheBuildNumberIsStillWorthShowing() {
        let appVersion = AppVersion(version: "", build: "2026.1013.2229")

        XCTAssertEqual(appVersion.displayText, "Build 2026.1013.2229")
    }

    /// どちらも読めなかったとき。黙って空行にしない。
    func testNeitherValueReadableSaysSo() {
        let appVersion = AppVersion(version: "", build: "")

        XCTAssertEqual(appVersion.displayText, "Version 不明")
    }

    /// 前後の空白は落とす。`Info.plist` の値に空白が混じっても形が崩れないように。
    func testSurroundingSpacesAreRemoved() {
        let appVersion = AppVersion(version: "  0.2.0 ", build: " 2026.1013.2229  ")

        XCTAssertEqual(appVersion.displayText, "Version 0.2.0 (2026.1013.2229)")
    }

    /// **読む鍵の名前を固定する。** ここを間違えると静かに空になり、
    /// 画面には「Version 不明」が出続ける。
    func testTheValuesComeFromTheBundlesOwnKeys() {
        let bundle = Bundle(for: AppVersionTests.self)
        let appVersion = AppVersion(bundle: bundle)

        XCTAssertEqual(
            appVersion.version,
            bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        )
        XCTAssertEqual(
            appVersion.build,
            bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        )
    }
}
