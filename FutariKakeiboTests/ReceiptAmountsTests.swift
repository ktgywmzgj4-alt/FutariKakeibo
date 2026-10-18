import XCTest
@testable import FutariKakeibo

/// レシート読み取りの第1段階: 読み取りの候補、金額のつじつま、明細の上限、店の見分け。
///
/// ここは**作った例**（回帰テスト）。実物のレシートでの正解率は `ReceiptScoreboardTests` で数える。
final class ReceiptAmountsTests: XCTestCase {
    private let calendar = ReceiptCorpus.calendar
    private let now = ReceiptCorpus.day(2026, 10, 18)

    private func line(
        _ text: String,
        x: Double = 0.08,
        width: Double = 0.5,
        y: Double,
        height: Double = 0.018
    ) -> RecognizedLine {
        RecognizedLine(text: text, minX: x, maxX: x + width, midY: y, height: height)
    }

    private func price(_ text: String, y: Double, alternatives: [String] = []) -> RecognizedLine {
        RecognizedLine(text: text, minX: 0.74, maxX: 0.93, midY: y, height: 0.018, alternatives: alternatives)
    }

    /// 店名・住所・電話・日付の4行。実物のレシートと同じく、明細の前に見出しがある形にする。
    private var header: [RecognizedLine] {
        [
            line("スーパーどこか", y: 0.04, height: 0.04),
            line("東京都港区芝公園4-2-8", y: 0.09),
            line("TEL 03-0000-0000", y: 0.12),
            line("2026/10/18 12:00", y: 0.15)
        ]
    }

    private func parse(_ lines: [RecognizedLine]) -> ReceiptDraft {
        ReceiptParser.parse(lines: lines, now: now, calendar: calendar)
    }

    // MARK: - 13品目以上

    /// 20品（22点）のレシート。以前は12件で打ち切っていた。
    func testALongReceiptIsNotCutOffAtTwelveItems() {
        let draft = parse(ReceiptCorpus.aeonOctober.lines)

        XCTAssertEqual(draft.items.count, 20)
        // 値引きを引いた和が、レシートの小計 5,105 と合う。品の値段は1つも変えていない。
        XCTAssertEqual(draft.items.reduce(0) { $0 + $1.netAmount }, 5_105)
        XCTAssertEqual(draft.amount, 5_524)
        XCTAssertFalse(draft.amountNeedsConfirmation)
    }

    // MARK: - クーポンと値引き

    func testADiscountIsAttachedToTheItemAboveWithoutChangingItsPrice() {
        let draft = parse(header + [
            line("豚こま切れ肉", y: 0.24), price("398", y: 0.24),
            line("割引 20%", y: 0.28), price("-80", y: 0.28),
            line("たまご", y: 0.32), price("248", y: 0.32),
            line("クーポン値引", y: 0.36), price("-50", y: 0.36),
            line("小計", y: 0.44), price("¥516", y: 0.44),
            line("合計", y: 0.50), price("¥516", y: 0.50)
        ])

        XCTAssertEqual(draft.items.map(\.name), ["豚こま切れ肉", "たまご"])
        XCTAssertEqual(draft.items.map(\.amount), [398, 248], "品の値段は刷られたまま")
        XCTAssertEqual(draft.items.map(\.discount), [80, 50])
        XCTAssertEqual(draft.amount, 516)
        XCTAssertFalse(draft.amountNeedsConfirmation)
    }

    /// 店番号の「-」を値引きと取り違えない。
    func testAHyphenInACodeIsNotADiscount() {
        let row = ReceiptParser.rows(from: [line("SS-38125", y: 0.2)])[0]
        XCTAssertNil(ReceiptParser.discountAmount(in: row))
    }

    // MARK: - 軽減税率8%と標準税率10%

    /// 外税が2つの率に分かれていても、小計＋外税で合計を確かめられる。
    /// 「合計」の語が読めていなくても、足し算が合う金額を選ぶ。
    func testOuterTaxAtBothRatesConfirmsTheTotalWithoutTheKeyword() {
        let draft = parse(header + [
            line("牛乳", y: 0.24), price("200※", y: 0.24),
            line("洗剤", y: 0.28), price("300", y: 0.28),
            line("小計", y: 0.36), price("¥500", y: 0.36),
            line("外税 8%対象額", y: 0.40), price("¥200", y: 0.40),
            line("外税 8%", y: 0.44), price("¥16", y: 0.44),
            line("外税10%対象額", y: 0.48), price("¥300", y: 0.48),
            line("外税10%", y: 0.52), price("¥30", y: 0.52),
            line("合言十", y: 0.58), price("¥546", y: 0.58)
        ])

        XCTAssertEqual(draft.amount, 546)
        XCTAssertEqual(draft.reconciledTotals, [546])
        XCTAssertTrue(draft.amountIsWellEvidenced)
        XCTAssertFalse(draft.amountNeedsConfirmation)
    }

    /// 内税は、合計に含まれる税の額で確かめる。8%でも10%でも、端数の扱いが違っても合えばよい。
    func testInnerTaxMatchesEitherRateAndAnyRounding() {
        XCTAssertTrue(ReceiptParser.innerTaxMatches(total: 2_964, tax: 269))   // 10%、切り捨て
        XCTAssertTrue(ReceiptParser.innerTaxMatches(total: 2_201, tax: 163))   // 8%
        XCTAssertTrue(ReceiptParser.innerTaxMatches(total: 1_350, tax: 100))   // 8%、割り切れる
        XCTAssertFalse(ReceiptParser.innerTaxMatches(total: 2_964, tax: 300))
    }

    // MARK: - 読み取りの候補の数字が食い違う

    /// 合計を「3,874」と読んだが、2番目の読み方は「3,374」。小計＋外税は 3,374。
    /// **足し算が合う読み方があるときだけ**選び直す。
    func testAnAlternativeReadingWinsWhenTheArithmeticAgrees() {
        let draft = parse(header + [
            line("ぶなしめじ", y: 0.24), price("¥98", y: 0.24),
            line("小計", y: 0.36), price("¥3,122", y: 0.36),
            line("外税 8%", y: 0.40), price("¥235", y: 0.40),
            line("外税10%", y: 0.44), price("¥17", y: 0.44),
            line("合計", y: 0.50), price("¥3,874", y: 0.50, alternatives: ["¥3,374", "¥3,814"])
        ])

        XCTAssertEqual(draft.amount, 3_374)
        XCTAssertFalse(draft.amountNeedsConfirmation)
    }

    /// 足し算の手がかりが無ければ、いちばん確からしい読み方のまま。数字を推測で補わない。
    func testAnAlternativeReadingIsNotUsedWithoutArithmetic() {
        let draft = parse(header + [
            line("ラーメン", y: 0.24), price("¥930", y: 0.24),
            line("合計", y: 0.32), price("¥930", y: 0.32, alternatives: ["¥980"])
        ])
        XCTAssertEqual(draft.amount, 930)
    }

    /// どの読み方も足し算と合わない。合計は書き換えず、利用者に確かめてもらう。
    func testATotalThatDisagreesWithTheArithmeticIsFlaggedNotRewritten() {
        let draft = parse(header + [
            line("ぶなしめじ", y: 0.24), price("¥98", y: 0.24),
            line("小計", y: 0.36), price("¥3,122", y: 0.36),
            line("外税 8%", y: 0.40), price("¥235", y: 0.40),
            line("外税10%", y: 0.44), price("¥17", y: 0.44),
            line("合計", y: 0.50), price("¥3,874", y: 0.50)
        ])

        XCTAssertEqual(draft.amount, 3_874, "合計を作り直さない")
        XCTAssertEqual(draft.reconciledTotals, [3_374])
        XCTAssertTrue(draft.amountNeedsConfirmation)
        XCTAssertFalse(draft.amountIsWellEvidenced)
        XCTAssertNotNil(draft.amountNote)
    }

    /// 合計の語も足し算の裏づけも無い金額は、確かめてもらう。
    func testATotalWithoutKeywordOrArithmeticAsksForConfirmation() {
        let draft = parse([
            line("あおぞら商店", y: 0.05, height: 0.04),
            line("りんご", y: 0.20), price("¥180", y: 0.20),
            line("みかん", y: 0.24), price("¥320", y: 0.24),
            line("¥2,000", x: 0.6, width: 0.3, y: 0.40)
        ])
        XCTAssertNotNil(draft.amount)
        XCTAssertTrue(draft.amountNeedsConfirmation)
    }

    /// お預り−お釣りで確かめる。
    func testCashTenderedMinusChangeConfirmsTheTotal() {
        let draft = parse(header + [
            line("食パン", y: 0.24), price("¥248", y: 0.24),
            line("合計", y: 0.32), price("¥248", y: 0.32),
            line("お預り", y: 0.36), price("¥1,000", y: 0.36),
            line("お釣り", y: 0.40), price("¥752", y: 0.40)
        ])
        XCTAssertEqual(draft.amount, 248)
        XCTAssertEqual(draft.reconciledTotals, [248])
        XCTAssertFalse(draft.amountNeedsConfirmation)
    }

    /// 富士サファリパークの1枚には「合計」の行が無い。支払額（クレジット）と小計・内税で確かめる。
    /// 以前は下の「1責 7653」の 7653 を合計にしていた。
    func testAReceiptWithoutATotalLineReadsTheCardPayment() {
        let draft = parse(ReceiptCorpus.fujiSafari.lines)
        XCTAssertEqual(draft.amount, 1_350)
        XCTAssertFalse(draft.amountNeedsConfirmation)
    }

    // MARK: - 数量と単価

    /// 「じゃがいも 116」の下の「(2個 X 単58)」。数×単価が値段と合うときだけ付ける。
    func testAQuantityLineBelowAnItemIsAttachedWhenTheNumbersAgree() {
        let draft = parse(header + [
            line("じゃがいも　バラ", y: 0.24), price("116※", y: 0.24),
            line("(2個 X 単58)", x: 0.12, width: 0.3, y: 0.28),
            line("きゅうり", y: 0.32), price("78※", y: 0.32),
            line("小計", y: 0.40), price("¥194", y: 0.40),
            line("合計", y: 0.44), price("¥194", y: 0.44)
        ])

        XCTAssertEqual(draft.items.map(\.amount), [116, 78])
        XCTAssertEqual(draft.items.first?.quantity, 2)
        XCTAssertEqual(draft.items.first?.unitPrice, 58)
        XCTAssertNil(draft.items.last?.quantity)
    }

    /// 品名の行に値段が無く、次の「1点※ ¥270」に値段が付く（ミスタードーナツ）。
    func testANameWithoutAPriceIsPairedWithTheQuantityLineBelow() {
        let draft = parse(header + [
            line("サクッと香る煮込みトマチキパイ", y: 0.24),
            line("1点※", x: 0.55, width: 0.12, y: 0.28), price("¥270", y: 0.28),
            line("オールドファッション", y: 0.32),
            line("1点※", x: 0.55, width: 0.12, y: 0.36), price("¥183", y: 0.36),
            line("合計 2点", y: 0.44), price("¥453", y: 0.44)
        ])

        XCTAssertEqual(draft.items.map(\.name), ["サクッと香る煮込みトマチキパイ", "オールドファッション"])
        XCTAssertEqual(draft.items.map(\.amount), [270, 183])
        XCTAssertEqual(draft.amount, 453)
    }

    // MARK: - 品名に % が入る品、字の間が空いた語

    func testAPercentInAProductNameDoesNotDropTheItem() {
        let draft = parse(header + [
            line("北海道純生クリーム35%", y: 0.24), price("¥418", y: 0.24),
            line("にがり１００％もめん", y: 0.28), price("48※", y: 0.28),
            line("氷結無糖GF7%", y: 0.32), price("¥178", y: 0.32),
            line("割引 10%", y: 0.36), price("-17", y: 0.36),
            line("合計", y: 0.44), price("¥627", y: 0.44)
        ])

        XCTAssertEqual(draft.items.map(\.name), ["北海道純生クリーム35%", "にがり１００％もめん", "氷結無糖GF7%"])
        XCTAssertEqual(draft.items.last?.discount, 17)
    }

    /// 税の行は % があるので落とす。読み違いの「内消費寺」も。
    func testTaxRowsWithAPercentAreStillNotItems() {
        let draft = parse(header + [
            line("牛乳", y: 0.24), price("¥188", y: 0.24),
            line("外8%", y: 0.28), price("¥15", y: 0.28),
            line("8%税", y: 0.32), price("¥15", y: 0.32),
            line("(内消費寺10%", y: 0.36), price("¥17)", y: 0.36),
            line("合計", y: 0.44), price("¥203", y: 0.44)
        ])
        XCTAssertEqual(draft.items.map(\.name), ["牛乳"])
    }

    /// イオンは「小　計」「合　計」と字の間を空けて刷る。品として拾わない。
    func testSpacedOutSubtotalAndTotalAreNotItems() {
        let draft = parse(header + [
            line("りんご", y: 0.24), price("¥300", y: 0.24),
            line("小　計", y: 0.32), price("¥300", y: 0.32),
            line("合　計", y: 0.36), price("¥300", y: 0.36)
        ])
        XCTAssertEqual(draft.items.map(\.name), ["りんご"])
    }

    /// 品名が数字で終わっても、右端の値段を使う（「国産豚ミンチ200」は 287 円）。
    func testANumberAtTheEndOfAProductNameIsNotItsPrice() {
        let draft = parse(header + [
            line("国産豚ミンチ２００", y: 0.24), price("287※", y: 0.24),
            line("合計", y: 0.32), price("¥287", y: 0.32)
        ])
        XCTAssertEqual(draft.items.first?.amount, 287)
    }

    // MARK: - 店の見分け（登録番号は事業者ごと）

    private let wonderCity = "イオンスタイルワンダーシティ\nTEL052-506-5600\n登録番号 T2040001000456"
    private let otherBranch = "イオンスタイル名古屋どこか\nTEL052-000-0000\n登録番号 T2040001000456"

    /// 同じ事業者の別の支店。登録番号は同じでも、店の鍵は電話番号で分かれる。
    func testTheSameInvoiceNumberAtAnotherBranchGivesAnotherShopKey() {
        let first = MerchantKey.make(fromReceiptText: wonderCity, merchant: "イオンスタイルワンダーシティ")
        let second = MerchantKey.make(fromReceiptText: otherBranch, merchant: "イオンスタイル名古屋どこか")

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(
            MerchantKey.businessKey(fromReceiptText: wonderCity),
            MerchantKey.businessKey(fromReceiptText: otherBranch)
        )
    }

    /// 別の支店のレシートには、覚えた支店の名前を入れない。種類（事業者で決まる）だけ使う。
    func testARememberedBranchNameIsNotPutOnAnotherBranch() {
        let memos = MerchantMemory.remembering(
            [],
            key: MerchantKey.make(fromReceiptText: wonderCity, merchant: "イオンスタイルワンダーシティ") ?? "",
            merchant: "イオンスタイルワンダーシティ",
            category: .groceries,
            businessKey: MerchantKey.businessKey(fromReceiptText: wonderCity),
            now: now
        )
        let draft = ReceiptDraft(
            merchant: "AEON STYLE",
            suggestedCategory: .other,
            recognizedText: otherBranch,
            shopKey: MerchantKey.make(fromReceiptText: otherBranch, merchant: "AEON STYLE"),
            businessKey: MerchantKey.businessKey(fromReceiptText: otherBranch)
        )

        let applied = MerchantMemory.applying(memos, to: draft)
        XCTAssertEqual(applied.merchant, "AEON STYLE")
        XCTAssertEqual(applied.suggestedCategory, .groceries)
    }

    /// 2026-10 より前は登録番号を鍵にして覚えていた。同じ支店のレシートなら（店名が刷られていれば）
    /// これまでどおり使う。別の支店には店名を入れない。
    func testAShopRememberedUnderTheOldInvoiceKeyStillWorksForTheSameBranch() {
        let memos = [
            MerchantMemo(key: "invoice:2040001000456", merchant: "イオンスタイルワンダーシティ", category: .groceries, updatedAt: now)
        ]
        let sameBranch = ReceiptDraft(
            merchant: "AEON STYLE",
            recognizedText: wonderCity,
            shopKey: "tel:0525065600",
            businessKey: "invoice:2040001000456"
        )
        let another = ReceiptDraft(
            merchant: "AEON STYLE",
            recognizedText: otherBranch,
            shopKey: "tel:0520000000",
            businessKey: "invoice:2040001000456"
        )

        XCTAssertEqual(MerchantMemory.applying(memos, to: sameBranch).merchant, "イオンスタイルワンダーシティ")
        XCTAssertEqual(MerchantMemory.applying(memos, to: another).merchant, "AEON STYLE")
        XCTAssertEqual(MerchantMemory.applying(memos, to: another).suggestedCategory, .groceries)
    }

    /// フリーダイヤルは会社全体の番号。店の見分けには使わない。
    func testAFreeDialNumberDoesNotIdentifyTheShop() {
        let key = MerchantKey.make(
            fromReceiptText: "お客様相談室 0120-000-000\n登録番号 T1234567890123",
            merchant: "どこかの店"
        )
        XCTAssertEqual(key, "invoice:1234567890123|どこかの店")
    }

    /// 「1点※」は店名ではない。ミスタードーナツで店名が「1点」になった。
    func testAQuantityIsNeverTheShopName() {
        XCTAssertFalse(ReceiptParser.isPlausibleMerchantName("1点"))
        XCTAssertFalse(ReceiptParser.isPlausibleMerchantName("1点※"))
        XCTAssertTrue(ReceiptParser.isPlausibleMerchantName("ミスタードーナツ"))
    }

    // MARK: - AIが誤った答えを返す

    /// 小計＋外税から合計が分かっているとき、それと違うAIの答えは受け取らない。
    func testAnAIAnswerThatDisagreesWithTheArithmeticIsRejected() {
        let base = ReceiptDraft(merchant: "コノミヤ 城西店", reconciledTotals: [3_374])
        let wrong = ReceiptAnswer(date: "", merchant: "", total: 33_740, category: "")
        let right = ReceiptAnswer(date: "", merchant: "", total: 3_374, category: "")

        XCTAssertNil(ReceiptInterpreter.merged(base: base, answer: wrong, now: now, calendar: calendar).amount)
        let merged = ReceiptInterpreter.merged(base: base, answer: right, now: now, calendar: calendar)
        XCTAssertEqual(merged.amount, 3_374)
        XCTAssertFalse(merged.amountNeedsConfirmation)
    }

    /// AIが数量を店名と答えても受け取らない。
    func testAnAIAnswerGivingAQuantityAsTheShopNameIsRejected() {
        let base = ReceiptDraft(merchant: "mister Donut")
        let answer = ReceiptAnswer(date: "", merchant: "1点", total: nil, category: "")
        let merged = ReceiptInterpreter.merged(base: base, answer: answer, now: now, calendar: calendar)
        XCTAssertEqual(merged.merchant, "mister Donut")
    }
}
