import XCTest
@testable import FutariKakeibo

final class ReceiptParserTests: XCTestCase {
    func testParsesJapaneseReceiptTotalMerchantAndDate() {
        let text = """
        ひだまりスーパー
        2026年8月13日
        食品 980
        日用品 254
        合計 ￥1,234
        """

        let draft = ReceiptParser.parse(text: text)

        XCTAssertEqual(draft.merchant, "ひだまりスーパー")
        XCTAssertEqual(draft.amount, 1_234)
        XCTAssertEqual(draft.suggestedCategory, .groceries)
        XCTAssertEqual(Calendar.current.component(.year, from: draft.date!), 2026)
        XCTAssertEqual(Calendar.current.component(.month, from: draft.date!), 8)
        XCTAssertEqual(Calendar.current.component(.day, from: draft.date!), 13)
    }

    func testTotalKeywordWinsOverOtherNumbers() {
        let amount = ReceiptParser.totalAmount(from: [
            "TEL 0521234567",
            "小計 4500",
            "合計 4,950"
        ])
        XCTAssertEqual(amount, 4_950)
    }
}
