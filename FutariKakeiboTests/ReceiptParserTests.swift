import XCTest
@testable import FutariKakeibo

final class ReceiptParserTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        return calendar
    }()

    /// 読み取り結果を再現するための行。x座標で品名と金額を分ける。
    private func line(
        _ text: String,
        x: Double = 0.08,
        width: Double = 0.5,
        y: Double,
        height: Double = 0.018
    ) -> RecognizedLine {
        RecognizedLine(text: text, minX: x, maxX: x + width, midY: y, height: height)
    }

    private func price(_ text: String, y: Double) -> RecognizedLine {
        RecognizedLine(text: text, minX: 0.74, maxX: 0.93, midY: y, height: 0.018)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    /// スーパーのレシートを想定した、位置つきの読み取り結果。
    private func supermarketReceipt() -> [RecognizedLine] {
        [
            line("スーパーひだまり", y: 0.05, height: 0.045),
            line("東京都渋谷区1-2-3", y: 0.10),
            line("TEL 03-1234-5678", y: 0.14),
            line("2026年8月29日 18:42", y: 0.20),
            line("牛乳", y: 0.28), price("198", y: 0.28),
            line("食パン", y: 0.33), price("248", y: 0.33),
            line("たまご", y: 0.38), price("298", y: 0.38),
            line("小計", y: 0.45), price("744", y: 0.45),
            line("消費税", y: 0.50), price("59", y: 0.50),
            line("合計", y: 0.55, height: 0.03), price("803", y: 0.55),
            line("お預り", y: 0.62), price("1,000", y: 0.62),
            line("お釣り", y: 0.67), price("197", y: 0.67)
        ]
    }

    private var referenceNow: Date { date(2026, 9, 2) }

    // MARK: - まとめて

    func testReadsWhenWhereWhatAndHowMuch() {
        let draft = ReceiptParser.parse(
            lines: supermarketReceipt(),
            now: referenceNow,
            calendar: calendar
        )

        XCTAssertEqual(draft.merchant, "スーパーひだまり")
        XCTAssertEqual(draft.date, date(2026, 8, 29))
        XCTAssertEqual(draft.amount, 803)
        XCTAssertEqual(draft.items.map(\.name), ["牛乳", "食パン", "たまご"])
        XCTAssertEqual(draft.items.map(\.amount), [198, 248, 298])
        XCTAssertEqual(draft.suggestedCategory, .groceries)
    }

    // MARK: - どこで

    func testPicksTheLargestTextNearTheTopAsTheShopName() {
        let lines = [
            line("いつもありがとうございます", y: 0.03),
            line("まるまる商店", y: 0.09, height: 0.05),
            line("担当 山田", y: 0.15)
        ]

        XCTAssertEqual(ReceiptParser.merchant(from: ReceiptParser.rows(from: lines)), "まるまる商店")
    }

    func testSkipsAddressPhoneAndDateWhenLookingForTheShopName() {
        let lines = [
            line("東京都港区芝公園4-2-8", y: 0.04),
            line("TEL 0120-123-456", y: 0.08),
            line("2026年8月29日", y: 0.12),
            line("あおぞらベーカリー", y: 0.16)
        ]

        XCTAssertEqual(ReceiptParser.merchant(from: ReceiptParser.rows(from: lines)), "あおぞらベーカリー")
    }

    // MARK: - いくら

    func testTotalKeywordWinsOverOtherNumbers() {
        let amount = ReceiptParser.totalAmount(from: [
            "TEL 0521234567",
            "小計 4500",
            "合計 4,950"
        ])
        XCTAssertEqual(amount, 4_950)
    }

    func testTotalIgnoresSubtotalChangeAndDeposit() {
        let lines = [
            line("小計", y: 0.30), price("744", y: 0.30),
            line("合計", y: 0.40), price("803", y: 0.40),
            line("お預り", y: 0.50), price("5,000", y: 0.50),
            line("お釣り", y: 0.60), price("4,197", y: 0.60)
        ]

        XCTAssertEqual(ReceiptParser.totalAmount(from: ReceiptParser.rows(from: lines)), 803)
    }

    func testTaxIncludedTotalIsStillATotal() {
        let lines = [line("税込合計", y: 0.4), price("1,320", y: 0.4)]
        XCTAssertEqual(ReceiptParser.totalAmount(from: ReceiptParser.rows(from: lines)), 1_320)
    }

    func testFallsBackToTheLargestAmountWithoutTheTotalKeyword() {
        let lines = [
            line("TEL 03-1234-5678", y: 0.1),
            line("りんご", y: 0.3), price("180", y: 0.3),
            line("ぶどう", y: 0.4), price("980", y: 0.4)
        ]

        XCTAssertEqual(ReceiptParser.totalAmount(from: ReceiptParser.rows(from: lines)), 980)
    }

    // MARK: - いつ

    func testReadsJapaneseEraDates() {
        XCTAssertEqual(
            ReceiptParser.date(in: "令和8年8月29日", now: referenceNow, calendar: calendar),
            date(2026, 8, 29)
        )
        XCTAssertEqual(
            ReceiptParser.date(in: "R8.8.29", now: referenceNow, calendar: calendar),
            date(2026, 8, 29)
        )
    }

    func testReadsTwoDigitYears() {
        XCTAssertEqual(
            ReceiptParser.date(in: "26/08/29 18:42", now: referenceNow, calendar: calendar),
            date(2026, 8, 29)
        )
    }

    func testTreatsAYearlessDateAsThisYear() {
        XCTAssertEqual(
            ReceiptParser.date(in: "8月29日", now: referenceNow, calendar: calendar),
            date(2026, 8, 29)
        )
    }

    func testRejectsDatesFarInTheFutureOrThePast() {
        XCTAssertNil(ReceiptParser.date(in: "2030年1月1日", now: referenceNow, calendar: calendar))
        XCTAssertNil(ReceiptParser.date(in: "2015年1月1日", now: referenceNow, calendar: calendar))
    }

    // MARK: - 何を

    func testItemsPairTheNameOnTheLeftWithThePriceOnTheRight() {
        let draft = ReceiptParser.parse(
            lines: supermarketReceipt(),
            now: referenceNow,
            calendar: calendar
        )

        XCTAssertEqual(draft.items.count, 3)
        XCTAssertFalse(draft.items.contains { $0.name.contains("小計") })
        XCTAssertFalse(draft.items.contains { $0.name.contains("東京都") })
        XCTAssertFalse(draft.items.contains { $0.amount == 803 })
    }

    func testPlainTextReceiptStillParses() {
        let text = """
        ひだまりスーパー
        2026年8月13日
        食品 980
        日用品 254
        合計 ￥1,234
        """

        let draft = ReceiptParser.parse(text: text, now: referenceNow, calendar: calendar)

        XCTAssertEqual(draft.merchant, "ひだまりスーパー")
        XCTAssertEqual(draft.amount, 1_234)
        XCTAssertEqual(draft.suggestedCategory, .groceries)
        XCTAssertEqual(draft.date, date(2026, 8, 13))
    }

    func testShopNameDecidesTheCategoryBeforeTheLineItems() {
        let lines = [
            line("スーパーひだまり", y: 0.05, height: 0.05),
            line("日用品", y: 0.3), price("254", y: 0.3),
            line("食品", y: 0.4), price("980", y: 0.4),
            line("合計", y: 0.5), price("1,234", y: 0.5)
        ]

        let draft = ReceiptParser.parse(lines: lines, now: referenceNow, calendar: calendar)
        XCTAssertEqual(draft.suggestedCategory, .groceries)
    }

    // MARK: - 実機で撮った実物のレシート

    /// ラーメン店のレシート。ロゴが大きく、本文に正式な店名が刷られている。
    private func ramenShopReceipt() -> [RecognizedLine] {
        [
            line("みんなの テンホウ", y: 0.03, height: 0.05),
            RecognizedLine(text: "WEL COME", minX: 0.62, maxX: 0.92, midY: 0.03, height: 0.03),
            line("岡谷長地店", y: 0.08, height: 0.03),
            line("<レシート 兼 領収書>", y: 0.11),
            line("テンホウ岡谷長地店", y: 0.14),
            line("登録番号:T2100001018500", y: 0.16),
            line("TEL:0266-27-2972", y: 0.18),
            line("長野県岡谷市長地梨久保1-6-21", y: 0.20),
            line("株式会社テンホウ・フーズ", y: 0.22),
            line("2026/08/29 18:54", y: 0.24), price("担:00", y: 0.24),
            line("肉揚味噌ラーメン", y: 0.28), price("¥930", y: 0.28),
            line("テンホウメン", y: 0.31), price("¥830", y: 0.31),
            line("ぎょうざ", y: 0.34), price("¥320", y: 0.34),
            line("小計 3点", y: 0.38), price("¥2,080", y: 0.38),
            line("合計", y: 0.42, height: 0.03), price("¥2,080", y: 0.42),
            line("(内消費税等", y: 0.45), price("¥189)", y: 0.45),
            line("(10%対象税込計", y: 0.47), price("¥2,080)", y: 0.47),
            line("クレジット支払", y: 0.50), price("¥2,080", y: 0.50),
            line("お釣", y: 0.52), price("¥0", y: 0.52)
        ]
    }

    /// スーパーのレシート。ロゴが店名で、上部にレジや会計機の記録が並ぶ。
    private func supermarketWithRegisterNumbers() -> [RecognizedLine] {
        [
            line("領収証", y: 0.02, height: 0.025),
            line("EQVo! エクボスタイル ファミリーテーブル", y: 0.05, height: 0.045),
            line("052-503-2116", y: 0.08),
            line("登録番号", y: 0.11), price("T2180001109424", y: 0.11),
            line("2026年08月30日(日)16:45", y: 0.13), price("レジ0103", y: 0.13),
            line("責No00000103会計機103", y: 0.15),
            line("スNo00000072小林", y: 0.17),
            line("スキャンレジ0004", y: 0.19), price("スキャンNo6539", y: 0.19),
            line("*天然水きりっと果実 ピン", y: 0.23), price("¥108", y: 0.23),
            line("*えくぼちゃんたまご", y: 0.27), price("¥248", y: 0.27),
            line("*豚小間切れ肉(中パック)", y: 0.29), price("¥396", y: 0.29),
            line("割引 10%", y: 0.31), price("-40", y: 0.31),
            line("*サンキスト パイン", y: 0.33), price("¥98", y: 0.33),
            line("*ホクト カットブナシメジ", y: 0.41), price("¥99", y: 0.41),
            line("小計", y: 0.45), price("¥1,361", y: 0.45),
            line("(外8% タイショウ", y: 0.47), price("¥1,361)", y: 0.47),
            line("外税計", y: 0.51), price("¥108", y: 0.51),
            line("(税合計", y: 0.53), price("¥108)", y: 0.53),
            line("合計", y: 0.55, height: 0.028), price("¥1,469", y: 0.55),
            line("クレジット", y: 0.58), price("¥1,469", y: 0.58),
            line("お釣り", y: 0.60), price("¥0", y: 0.60),
            line("お買上点数", y: 0.62), price("9点", y: 0.62)
        ]
    }

    func testRamenShopReceiptPrefersThePrintedShopNameOverTheLogo() {
        let draft = ReceiptParser.parse(
            lines: ramenShopReceipt(),
            now: referenceNow,
            calendar: calendar
        )

        XCTAssertEqual(draft.merchant, "テンホウ岡谷長地店")
        XCTAssertEqual(draft.amount, 2_080)
        XCTAssertEqual(draft.date, date(2026, 8, 29))
        XCTAssertEqual(draft.items.map(\.name), ["肉揚味噌ラーメン", "テンホウメン", "ぎょうざ"])
        XCTAssertEqual(draft.items.map(\.amount), [930, 830, 320])
        XCTAssertEqual(draft.suggestedCategory, .dining)
    }

    /// 金額の断片が1行ぶんずれて隣の行に付くと、品名と金額の対応が全部ずれる。
    func testAPriceThatDriftsIntoThePreviousRowDoesNotShiftEveryItem() {
        let drifted = [
            line("肉揚味噌ラーメン", y: 0.28), price("¥930", y: 0.28),
            RecognizedLine(text: "¥830", minX: 0.74, maxX: 0.93, midY: 0.283, height: 0.018),
            line("テンホウメン", y: 0.31),
            line("合計", y: 0.42), price("¥1,760", y: 0.42)
        ]

        let draft = ReceiptParser.parse(lines: drifted, now: referenceNow, calendar: calendar)

        XCTAssertEqual(draft.items.first?.name, "肉揚味噌ラーメン")
        XCTAssertEqual(draft.items.first?.amount, 930)
    }

    func testSupermarketReceiptSkipsRegisterAndTaxRows() {
        let draft = ReceiptParser.parse(
            lines: supermarketWithRegisterNumbers(),
            now: referenceNow,
            calendar: calendar
        )

        XCTAssertEqual(draft.merchant, "EQVo! エクボスタイル ファミリーテーブル")
        XCTAssertEqual(draft.amount, 1_469)
        XCTAssertEqual(draft.date, date(2026, 8, 30))
        XCTAssertEqual(
            draft.items.map(\.name),
            ["天然水きりっと果実 ピン", "えくぼちゃんたまご", "豚小間切れ肉(中パック)", "サンキスト パイン", "ホクト カットブナシメジ"]
        )
        XCTAssertFalse(draft.items.contains { $0.name.contains("スキャン") })
        XCTAssertFalse(draft.items.contains { $0.name.contains("タイショウ") })
        XCTAssertFalse(draft.items.contains { $0.amount == 1_361 })
    }

    func testFullWidthDigitsAreNormalizedWithoutTouchingKatakana() {
        let lines = [
            line("ラーメン", y: 0.3), price("９３０", y: 0.3),
            line("合計", y: 0.5), price("９３０", y: 0.5)
        ]

        let draft = ReceiptParser.parse(lines: lines, now: referenceNow, calendar: calendar)

        XCTAssertEqual(draft.amount, 930)
        XCTAssertEqual(draft.items.first?.name, "ラーメン")
    }

    // MARK: - 合計が読みにくい形のレシート

    /// 「合計」は大きく刷られ、語と金額が別の行として読まれることがある。
    func testTotalReadsTheNextRowWhenTheAmountIsSplitOff() {
        let lines = [
            line("ラーメン", y: 0.30), price("¥930", y: 0.30),
            line("合計", y: 0.50, height: 0.032),
            price("¥2,080", y: 0.54),
            line("レシートNo.077654", y: 0.70)
        ]

        let draft = ReceiptParser.parse(lines: lines, now: referenceNow, calendar: calendar)
        XCTAssertEqual(draft.amount, 2_080)
    }

    /// 合計の語が読めなかったとき、桁の大きいレシート番号を拾ってはいけない。
    func testReceiptNumberIsNotMistakenForTheTotal() {
        let lines = [
            line("あおぞら商店", y: 0.05, height: 0.04),
            line("2026/08/29", y: 0.10),
            line("商品A", y: 0.20), price("¥930", y: 0.20),
            line("商品B", y: 0.24), price("¥830", y: 0.24),
            line("商品C", y: 0.28), price("¥320", y: 0.28),
            line("レシートNo.077654", y: 0.60)
        ]

        let draft = ReceiptParser.parse(lines: lines, now: referenceNow, calendar: calendar)
        XCTAssertEqual(draft.amount, 2_080)
    }

    func testProductCodesAreStrippedFromItemNames() {
        let lines = [
            line("外8 1501 鮮魚(かご盛り)", y: 0.30), price("¥450", y: 0.30),
            line("外8 2205 ふぐ唐揚げ", y: 0.34), price("¥690", y: 0.34),
            line("合計", y: 0.50), price("¥1,140", y: 0.50)
        ]

        let draft = ReceiptParser.parse(lines: lines, now: referenceNow, calendar: calendar)
        XCTAssertEqual(draft.items.map(\.name), ["鮮魚(かご盛り)", "ふぐ唐揚げ"])
        XCTAssertEqual(draft.amount, 1_140)
    }

    func testQuantityRowsAreNotItems() {
        let lines = [
            line("サクレパイン", y: 0.30),
            line("2コX単118", y: 0.33), price("¥236", y: 0.33),
            line("合計", y: 0.50), price("¥236", y: 0.50)
        ]

        let draft = ReceiptParser.parse(lines: lines, now: referenceNow, calendar: calendar)
        XCTAssertFalse(draft.items.contains { $0.name.contains("コX単") })
    }
}
