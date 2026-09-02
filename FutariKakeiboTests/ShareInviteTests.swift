import XCTest
@testable import FutariKakeibo

final class ShareInviteTests: XCTestCase {
    func testGeneratedCodeUsesOnlyUnmistakableCharacters() {
        for _ in 0..<200 {
            let code = ShareInvite.makeCode()
            XCTAssertEqual(code.count, ShareInvite.codeLength)
            XCTAssertTrue(code.allSatisfy { ShareInvite.alphabet.contains($0) })
            // 0 O 1 I L は口頭でも画面でも見分けがつかないので使わない。
            XCTAssertFalse(code.contains { "0O1IL".contains($0) })
        }
    }

    func testCodesAreNotAllTheSame() {
        let codes = Set((0..<50).map { _ in ShareInvite.makeCode() })
        XCTAssertGreaterThan(codes.count, 45)
    }

    func testTypedCodeIsNormalizedBeforeMatching() {
        XCTAssertEqual(ShareInvite.normalized("abcd-2345"), "ABCD2345")
        XCTAssertEqual(ShareInvite.normalized("ABCD 2345"), "ABCD2345")
        XCTAssertEqual(ShareInvite.normalized(" abcd2345 "), "ABCD2345")
    }

    func testDisplayCodeIsSplitInTheMiddle() {
        XCTAssertEqual(ShareInvite.formatted("ABCD2345"), "ABCD-2345")
        XCTAssertEqual(ShareInvite.formatted("abcd-2345"), "ABCD-2345")
    }

    func testCompletenessNeedsTheFullLength() {
        XCTAssertFalse(ShareInvite.isComplete("ABCD-234"))
        XCTAssertTrue(ShareInvite.isComplete("ABCD-2345"))
        XCTAssertTrue(ShareInvite.isComplete("abcd2345"))
    }

    func testExpiryIsReportedFromTheStoredDate() {
        let invite = ShareInvite(
            code: "ABCD2345",
            shareURL: URL(fileURLWithPath: "/tmp/share"),
            expiresAt: Date.now.addingTimeInterval(-60)
        )
        XCTAssertTrue(invite.isExpired)

        let fresh = ShareInvite(
            code: "ABCD2345",
            shareURL: URL(fileURLWithPath: "/tmp/share"),
            expiresAt: Date.now.addingTimeInterval(ShareInvite.lifetime)
        )
        XCTAssertFalse(fresh.isExpired)
        XCTAssertTrue(fresh.remainingDescription.contains("時間"))
    }
}
