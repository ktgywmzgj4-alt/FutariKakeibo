import XCTest
@testable import FutariKakeibo

/// 端末の中のAIそのものはCIでは動かない（Apple Intelligenceが無い）。
/// 動かせるのは「AIの答えをどう受け取り、どこで捨てるか」の部分なので、そこを検査する。
final class ReceiptInterpreterTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 3)) ?? .distantPast
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    // MARK: - 答えの読み取り

    func testAnswerIsReadFromTheFourLines() {
        let answer = ReceiptAnswer.parse("""
        date: 2026-08-30
        merchant: Selfix北名古屋
        total: 2964
        category: transportation
        """)

        XCTAssertEqual(answer?.merchant, "Selfix北名古屋")
        XCTAssertEqual(answer?.total, 2_964)
        XCTAssertEqual(answer?.category, "transportation")
        XCTAssertEqual(answer?.parsedDate(calendar: calendar), date(2026, 8, 30))
    }

    /// AIは前置きや箇条書きの記号を付けてくることがある。
    func testAnswerSurvivesExtraDecoration() {
        let answer = ReceiptAnswer.parse("""
        はい、読み取りました。

        - date: 2026/08/30
        - merchant:  ローソン 北名古屋店
        - total: ¥1,480
        - category: GROCERIES
        """)

        XCTAssertEqual(answer?.merchant, "ローソン 北名古屋店")
        XCTAssertEqual(answer?.total, 1_480)
        XCTAssertEqual(answer?.category, "groceries")
        XCTAssertEqual(answer?.parsedDate(calendar: calendar), date(2026, 8, 30))
    }

    func testAnswerWithoutAnyFieldIsNil() {
        XCTAssertNil(ReceiptAnswer.parse("読み取れませんでした"))
    }

    // MARK: - どこで捨てるか

    /// AIが答えた4項目でルールの結果を置き換える。
    func testAnswerReplacesTheRuleResult() {
        let base = ReceiptDraft(
            merchant: "写北名古屋",
            amount: 38_125,
            date: date(2026, 8, 30),
            suggestedCategory: .other
        )
        let answer = ReceiptAnswer(
            date: "2026-08-30",
            merchant: "Selfix北名古屋",
            total: 2_964,
            category: "transportation"
        )

        let merged = ReceiptInterpreter.merged(
            base: base, answer: answer, now: now, calendar: calendar
        )
        XCTAssertEqual(merged.merchant, "Selfix北名古屋")
        XCTAssertEqual(merged.amount, 2_964)
        XCTAssertEqual(merged.suggestedCategory, .transportation)
    }

    /// AIが答えられなかった項目は、ルールの結果をそのまま残す。
    /// **AIを足したことで今より悪くなることはない**、というのがこの検査の主旨。
    func testEmptyAnswerKeepsTheRuleResult() {
        let base = ReceiptDraft(
            merchant: "あおぞら商店",
            amount: 2_080,
            date: date(2026, 8, 29),
            suggestedCategory: .groceries
        )
        let answer = ReceiptAnswer(date: "", merchant: "", total: nil, category: "")

        let merged = ReceiptInterpreter.merged(
            base: base, answer: answer, now: now, calendar: calendar
        )
        XCTAssertEqual(merged.merchant, "あおぞら商店")
        XCTAssertEqual(merged.amount, 2_080)
        XCTAssertEqual(merged.date, date(2026, 8, 29))
        XCTAssertEqual(merged.suggestedCategory, .groceries)
    }

    /// 知らない種類を答えてきたら捨てる。
    func testUnknownCategoryIsIgnored() {
        let base = ReceiptDraft(merchant: "店", suggestedCategory: .groceries)
        let answer = ReceiptAnswer(
            date: "", merchant: "", total: nil, category: "ガソリン"
        )

        let merged = ReceiptInterpreter.merged(
            base: base, answer: answer, now: now, calendar: calendar
        )
        XCTAssertEqual(merged.suggestedCategory, .groceries)
    }

    /// レシートは過去のもの。未来の日付は読み違いなので採用しない。
    func testFutureDateIsIgnored() {
        let base = ReceiptDraft(merchant: "店", date: date(2026, 8, 30))
        let answer = ReceiptAnswer(
            date: "2027-01-01", merchant: "", total: nil, category: ""
        )

        let merged = ReceiptInterpreter.merged(
            base: base, answer: answer, now: now, calendar: calendar
        )
        XCTAssertEqual(merged.date, date(2026, 8, 30))
    }

    func testZeroTotalIsIgnored() {
        let base = ReceiptDraft(merchant: "店", amount: 2_080)
        let answer = ReceiptAnswer(date: "", merchant: "", total: 0, category: "")

        let merged = ReceiptInterpreter.merged(
            base: base, answer: answer, now: now, calendar: calendar
        )
        XCTAssertEqual(merged.amount, 2_080)
    }

    /// 文字が何も無ければAIを呼ばない。
    func testEmptyTextIsNotSentToTheModel() async {
        let answer = await OnDeviceReceiptReader.read(text: "   \n  ")
        XCTAssertNil(answer)
    }

    /// AIが使えない環境（CIはこちら）でも、ルールの結果がそのまま返る。
    func testInterpretFallsBackToRules() async {
        let lines = [
            RecognizedLine(text: "あおぞら商店", midY: 0.05, height: 0.04),
            RecognizedLine(text: "2026/08/29", midY: 0.10),
            RecognizedLine(text: "合計", minX: 0.08, maxX: 0.3, midY: 0.50),
            RecognizedLine(text: "¥2,080", minX: 0.74, maxX: 0.93, midY: 0.50)
        ]

        let draft = await ReceiptInterpreter.interpret(
            lines: lines, now: now, calendar: calendar
        )
        XCTAssertEqual(draft.amount, 2_080)
        XCTAssertEqual(draft.date, date(2026, 8, 29))
    }
}
