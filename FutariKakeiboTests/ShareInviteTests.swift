import CloudKit
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

    // MARK: - 失敗したときに出す言葉

    /// 何が起きたか分からない失敗でも、日本語で短く伝える。
    /// iCloudの返す言葉は英語なので、そのまま出さない。
    func testAnUnknownFailureIsExplainedInPlainJapanese() {
        let message = AppStore.inviteFailureMessage(
            for: NSError(domain: "test", code: -1, userInfo: nil)
        )
        XCTAssertEqual(message, "合言葉を発行できませんでした。もう一度お試しください。")
    }

    /// 家計が無いなど、そもそも始められないときも同じ言葉を出す。黙って終わらない。
    func testNoErrorAtAllStillProducesAMessage() {
        XCTAssertEqual(
            AppStore.inviteFailureMessage(for: nil),
            "合言葉を発行できませんでした。もう一度お試しください。"
        )
    }

    /// 利用者が自分で直せる失敗は、何をすればよいかまで伝える。
    func testNotSignedInTellsThePersonWhatToDo() {
        let message = AppStore.inviteFailureMessage(for: CKError(.notAuthenticated))
        XCTAssertTrue(message.contains("iCloudにサインイン"), message)
    }

    func testANetworkFailureMentionsTheConnection() {
        let message = AppStore.inviteFailureMessage(for: CKError(.networkUnavailable))
        XCTAssertTrue(message.contains("通信"), message)
    }

    /// もともと日本語の説明を持っている失敗は、その言葉のまま出す。
    /// ひとまとめの「発行できませんでした」で上書きしない。
    func testAKnownFailureKeepsItsOwnWords() {
        let message = AppStore.inviteFailureMessage(
            for: CloudKitSyncService.SyncError.inviteExpired
        )
        XCTAssertTrue(message.contains("期限"), message)
        XCTAssertFalse(message.contains("発行できませんでした"), message)
    }

    /// 参加するときの失敗に「発行できませんでした」とは出さない。
    func testJoiningUsesItsOwnWording() {
        let message = AppStore.inviteFailureMessage(
            for: NSError(domain: "test", code: -1, userInfo: nil),
            fallback: "この合言葉では参加できませんでした。もう一度お試しください。"
        )
        XCTAssertEqual(message, "この合言葉では参加できませんでした。もう一度お試しください。")
    }
}
