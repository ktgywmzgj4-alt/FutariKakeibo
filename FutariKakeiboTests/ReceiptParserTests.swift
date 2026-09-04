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
            line("お買上げ", y: 0.40), price("¥2,080", y: 0.40),
            line("レシートNo.077654", y: 0.60)
        ]

        // 合計の語が読めなかった場合でも、明細の和に合う2,080を選び、
        // 桁の大きいレシート番号のほうへは行かない。
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

    /// Selfix北名古屋のガソリンのレシート。実機で合計を¥38,125と読み違えていた。
    /// 店番号 SS-38125 を金額として拾ってしまうのが原因だった。
    func testStationCodeIsNotMistakenForTheTotal() {
        let lines = [
            line("Selfix北名古屋", y: 0.06, height: 0.035),
            line("愛知県北名古屋市鹿田東村79", y: 0.12),
            line("SS-38125", x: 0.62, width: 0.24, y: 0.12),
            line("TEL:0568-54-1790", y: 0.15),
            line("登録番号：T2170001007389", y: 0.18),
            line("2026年08月30日 11:46", y: 0.22),
            line("伝票No.0596", x: 0.62, width: 0.24, y: 0.22),
            line("0200", y: 0.32), price("¥2964", y: 0.32),
            line("レギュラーガソリン P19", y: 0.35),
            line("19.12(L)", x: 0.58, width: 0.2, y: 0.35),
            line("数量", y: 0.38),
            line("@155", x: 0.66, width: 0.14, y: 0.38),
            line("単価", y: 0.41),
            line("合計", y: 0.48, height: 0.03), price("¥2,964", y: 0.48),
            line("(内税分消費税", y: 0.52), price("¥269)", y: 0.52),
            line("端末番号:0804839738125", y: 0.62)
        ]

        let draft = ReceiptParser.parse(lines: lines, now: referenceNow, calendar: calendar)
        XCTAssertEqual(draft.amount, 2_964)
        XCTAssertEqual(draft.date, date(2026, 8, 30))
    }

    /// 給油機の表示。「数量 @155」「単価」は買ったものではないので明細に出さない。
    func testFuelPumpReadoutsAreNotItems() {
        let lines = [
            line("0200", y: 0.32), price("¥2964", y: 0.32),
            line("数量", y: 0.38),
            line("@155", x: 0.66, width: 0.14, y: 0.38),
            line("単価", y: 0.41),
            line("合計", y: 0.48), price("¥2,964", y: 0.48)
        ]

        let draft = ReceiptParser.parse(lines: lines, now: referenceNow, calendar: calendar)
        XCTAssertFalse(draft.items.contains { $0.name.contains("数量") })
        XCTAssertFalse(draft.items.contains { $0.amount == 155 })
        XCTAssertFalse(draft.items.contains { $0.amount == 200 })
    }

    /// 商品コード、単価、給油量、カード番号の末尾。どれも金額ではない。
    func testCodesAndUnitPricesAreNotAmounts() {
        let lines = [
            line("XXXXXXXXXXXX6941", y: 0.26),
            line("ATC:004B", y: 0.28),
            line("8620-8623 07", y: 0.30),
            line("合計", y: 0.50), price("¥1,180", y: 0.50)
        ]

        let draft = ReceiptParser.parse(lines: lines, now: referenceNow, calendar: calendar)
        XCTAssertEqual(draft.amount, 1_180)
    }

    // MARK: - 2026-09-04 実機で外した実物のレシート

    /// 白馬のカフェ。1行目の `[領収書]` が `[領収害]` と読まれ、それを店名にしていた。
    /// 「領収書」で弾いていたので、1文字違うだけで素通りした。
    private func cafeReceiptWithReceiptHeading() -> [RecognizedLine] {
        [
            line("[領収害]", y: 0.05, height: 0.022),
            line("CHAVATY HAKUBA", y: 0.08, height: 0.022),
            line("長野県 北安曇郡", y: 0.11),
            line("白馬村 北城 12056", y: 0.14),
            line("TEL:0261-72-2474", y: 0.17),
            line("登録番号:T9100001017140", y: 0.20),
            line("2026/08/28 10:25:21", y: 0.25),
            line("レジ:0007 担当:0001", y: 0.28),
            line("伝票名:伝票00078069", y: 0.31),
            line("サマーリリカル中井ラテ", y: 0.37),
            line("¥780 1点", y: 0.40), price("¥780", y: 0.40),
            line("単)C 抹茶ラテ", y: 0.44),
            line("オリジナル", y: 0.47),
            line("¥780 1点", y: 0.50), price("¥780", y: 0.50),
            line("小計 2点", y: 0.55), price("¥1,560", y: 0.55),
            line("合計", y: 0.60, height: 0.03), price("¥1,560", y: 0.60),
            line("(10%標準対象", y: 0.63), price("¥1,560)", y: 0.63),
            line("お預り", y: 0.69), price("¥1,560", y: 0.69),
            line("お釣り", y: 0.72), price("¥0", y: 0.72)
        ]
    }

    func testReceiptHeadingIsNotTheShopNameEvenWhenMisread() {
        let draft = ReceiptParser.parse(
            lines: cafeReceiptWithReceiptHeading(),
            now: referenceNow,
            calendar: calendar
        )

        XCTAssertEqual(draft.merchant, "CHAVATY HAKUBA")
        XCTAssertEqual(draft.amount, 1_560)
        XCTAssertEqual(draft.date, date(2026, 8, 28))
    }

    /// パン屋。ロゴが黒地に白抜きで読めず、`登録名称 株式会社マナの森` の行が店名になっていた。
    /// さらに合計が ¥8 になった。「合計」の語は読めたが金額が離れた行として読まれ、
    /// あいだに `(税率 8%対象額` が入ったため、そこから 8 を拾っていた。
    private func bakeryReceiptWithLabelledName() -> [RecognizedLine] {
        [
            line("登録番号 T6180001124618", y: 0.06),
            line("登録名称 株式会社マナの森", y: 0.09),
            line("北名古屋市熊之庄八幡213", y: 0.12),
            line("TEL/FAX 0568-23-0533", y: 0.15),
            line("www.mana-mori.com", y: 0.18),
            line("2026年 8月 1日(土)12:04 #000002", y: 0.23),
            line("000001 000001 0641", y: 0.26),
            line("内8 バケットピッツァ", y: 0.33), price("¥388", y: 0.33),
            line("内8 ねぎ味噌ベーコンタルテ", y: 0.36), price("¥388", y: 0.36),
            line("内8 エビカツサンド", y: 0.39), price("¥540", y: 0.39),
            line("内8 塩パンスモークチキン", y: 0.42), price("¥583", y: 0.42),
            line("内8 オサツデニッシュ", y: 0.45), price("¥302", y: 0.45),
            line("小計", y: 0.52), price("¥2,201", y: 0.52),
            line("(内税対象額", y: 0.55), price("¥2,201)", y: 0.55),
            line("買上点数", y: 0.58), price("5点", y: 0.58),
            line("合計", y: 0.64, height: 0.032),
            line("(税率 8%対象額", y: 0.67),
            price("¥2,201", y: 0.70),
            line("(内消費税等 8%", y: 0.73), price("¥163)", y: 0.73),
            line("クレジット", y: 0.77), price("¥2,201", y: 0.77)
        ]
    }

    func testBakeryReceiptReadsTheTotalPastTheTaxRateRow() {
        let draft = ReceiptParser.parse(
            lines: bakeryReceiptWithLabelledName(),
            now: referenceNow,
            calendar: calendar
        )

        XCTAssertEqual(draft.amount, 2_201)
        XCTAssertEqual(draft.merchant, "株式会社マナの森")
        XCTAssertEqual(draft.date, date(2026, 8, 1))
    }

    /// 税率の `8%` の 8 は金額ではない。合計の金額が別の行にあるときに拾っていた。
    func testAPercentageIsNeverAnAmount() {
        let lines = [
            line("パン工房", y: 0.05, height: 0.04),
            line("2026/08/01", y: 0.10),
            line("食パン", y: 0.20), price("¥300", y: 0.20),
            line("合計", y: 0.40, height: 0.03),
            line("(税率 8%対象額", y: 0.45),
            price("¥300", y: 0.50)
        ]

        let draft = ReceiptParser.parse(lines: lines, now: referenceNow, calendar: calendar)
        XCTAssertEqual(draft.amount, 300)
    }

    /// 合計の語のあとに読めた数字が、明細の合計よりずっと小さいときは信じない。
    func testATotalFarBelowTheItemsIsRejected() {
        let lines = [
            line("あおぞら商店", y: 0.05, height: 0.04),
            line("2026/08/29", y: 0.10),
            line("商品A", y: 0.20), price("¥1,200", y: 0.20),
            line("商品B", y: 0.24), price("¥800", y: 0.24),
            line("合計", y: 0.40, height: 0.03),
            line("5点", y: 0.45),
            price("¥2,000", y: 0.50)
        ]

        let draft = ReceiptParser.parse(lines: lines, now: referenceNow, calendar: calendar)
        XCTAssertEqual(draft.amount, 2_000)
    }

    // MARK: - 斜めから撮ったレシート

    /// 斜めから撮った1枚を再現する。
    ///
    /// 実物の写真では、同じ行でも右端にある金額のほうが、左端にある品名より
    /// 上（または下）へずれる。ずれ幅は「中央からの横の距離 × 傾き」。
    /// `slope` には、読み取りが文字の四隅から測った傾きをそのまま入れる。
    private func slanted(_ lines: [RecognizedLine], slope: Double) -> [RecognizedLine] {
        lines.map { source in
            var moved = source
            moved.slope = slope
            moved.midY = source.midY + slope * (source.midX - 0.5)
            return moved
        }
    }

    /// 品名が左、金額が右に離れて並ぶ、ごく普通のレシート。
    private func cornerStoreReceipt() -> [RecognizedLine] {
        [
            line("まちかどストア", y: 0.06, height: 0.045),
            line("東京都杉並区4-5-6", y: 0.11),
            line("TEL 03-9876-5432", y: 0.15),
            line("2026年8月30日 10:12", y: 0.19),
            line("りんご", y: 0.30), price("198", y: 0.30),
            line("食パン", y: 0.35), price("248", y: 0.35),
            line("たまご", y: 0.40), price("298", y: 0.40),
            line("合計", y: 0.50, height: 0.03), price("744", y: 0.50)
        ]
    }

    /// 斜めから撮ると、右にある金額がひとつ下の行の品名と同じ高さに来る。
    ///
    /// 直す前は「食パン 198円」「たまご 248円」と、**ひとつずつずれた値段**が付いていた。
    /// 金額そのものは読めているので気づきにくい。
    func testASlantedPhotoStillPairsEachNameWithItsOwnPrice() {
        let draft = ReceiptParser.parse(
            lines: slanted(cornerStoreReceipt(), slope: 0.10),
            now: referenceNow,
            calendar: calendar
        )

        XCTAssertEqual(draft.items, [
            ReceiptItem(name: "りんご", amount: 198),
            ReceiptItem(name: "食パン", amount: 248),
            ReceiptItem(name: "たまご", amount: 298)
        ])
        XCTAssertEqual(draft.amount, 744)
        XCTAssertEqual(draft.merchant, "まちかどストア")
    }

    /// 傾きを直したあとの結果は、正面から撮った1枚とまったく同じでなければならない。
    func testASlantedPhotoReadsTheSameAsAStraightOne() {
        let straight = ReceiptParser.parse(
            lines: cornerStoreReceipt(),
            now: referenceNow,
            calendar: calendar
        )
        let slantedDraft = ReceiptParser.parse(
            lines: slanted(cornerStoreReceipt(), slope: -0.08),
            now: referenceNow,
            calendar: calendar
        )

        XCTAssertEqual(slantedDraft.items, straight.items)
        XCTAssertEqual(slantedDraft.amount, straight.amount)
        XCTAssertEqual(slantedDraft.merchant, straight.merchant)
        XCTAssertEqual(slantedDraft.date, straight.date)
    }

    /// 読み取りがありえない傾きを返してきたら、使わない。
    ///
    /// 正面から撮った1枚の位置はそのままで、傾きの値だけが壊れている状態。
    /// これを信じて動かすと、まっすぐ撮った写真まで崩れてしまう。
    func testAnImpossibleTiltIsIgnored() {
        var lines = cornerStoreReceipt()
        for index in lines.indices {
            lines[index].slope = 5.0
        }

        let draft = ReceiptParser.parse(lines: lines, now: referenceNow, calendar: calendar)

        XCTAssertEqual(draft.items, [
            ReceiptItem(name: "りんご", amount: 198),
            ReceiptItem(name: "食パン", amount: 248),
            ReceiptItem(name: "たまご", amount: 298)
        ])
        XCTAssertEqual(draft.amount, 744)
    }

    /// 傾きは1枚ぶんの中央値で決める。1か所の読み違いで全体が動かないこと。
    func testOneBadlyMeasuredFragmentDoesNotTiltTheWholeReceipt() {
        var lines = slanted(cornerStoreReceipt(), slope: 0.10)
        lines[4].slope = -4.0

        let draft = ReceiptParser.parse(lines: lines, now: referenceNow, calendar: calendar)

        XCTAssertEqual(draft.items, [
            ReceiptItem(name: "りんご", amount: 198),
            ReceiptItem(name: "食パン", amount: 248),
            ReceiptItem(name: "たまご", amount: 298)
        ])
    }

    // MARK: - マクドナルドのレシート（実物）

    /// 名古屋市西区のマクドナルドで撮った1枚。
    ///
    /// 店名に **「営業時間 24時間営業」** が入ってしまい、種類も「その他」になった。
    /// 金額 2,230円 と日付だけが正しく読めていた。
    private func mcdonaldsReceipt() -> [RecognizedLine] {
        [
            line("マクドナルド城町店", y: 0.04, height: 0.030),
            line("名古屋市西区平中町352", y: 0.055),
            line("052-501-5031", y: 0.070),
            line("営業時間 24時間営業", y: 0.085),
            line("登録番号: T5011101033783", y: 0.100),
            line("84 レジNO 14", x: 0.08, width: 0.25, y: 0.125),
            line("2026年9月4日 (金)19:54", x: 0.50, width: 0.42, y: 0.125),
            line("(ツキミバーガーセット)", y: 0.16), price("800", y: 0.16),
            line("ツキミバーガー", y: 0.175),
            line("チキンマックナゲット5ピース", y: 0.190),
            line("Qoo シロブドウ M", y: 0.205),
            line("(チーズツキミセット)", y: 0.220), price("830", y: 0.220),
            line("マックフライポテトM", y: 0.235),
            line("(ポテナゲ ダイ)", y: 0.250), price("600", y: 0.250),
            line("マックフライポテトL", y: 0.265),
            line("小計", y: 0.40), price("¥2,230", y: 0.40),
            line("(内消費税", y: 0.42), price("¥165)", y: 0.42),
            line("8%対象", y: 0.44), price("¥2,230", y: 0.44),
            line("合計", y: 0.47), price("¥2,230", y: 0.47),
            line("クレジット支払", y: 0.49), price("¥2,230", y: 0.49),
            line("おつり", y: 0.51), price("¥0", y: 0.51)
        ]
    }

    /// 金額・店名・種類の3つがそろうこと。レシート読み取りでいちばん大事な3項目。
    func testMcDonaldsReceiptReadsTheShopTheAmountAndTheKind() {
        let draft = ReceiptParser.parse(
            lines: mcdonaldsReceipt(),
            now: date(2026, 9, 5),
            calendar: calendar
        )

        XCTAssertEqual(draft.merchant, "マクドナルド城町店")
        XCTAssertEqual(draft.amount, 2_230)
        XCTAssertEqual(draft.suggestedCategory, .dining)
        XCTAssertEqual(draft.date, date(2026, 9, 4))
    }

    /// 「町」が1文字入っているだけで住所とみなしていた。
    /// 日本の店名には 町・市・区 がふつうに入る（城町店・本町店・北名古屋店）。
    func testAShopNameContainingATownCharacterIsNotAnAddress() {
        for name in ["マクドナルド城町店", "スーパー本町店", "コメダ珈琲店 大手町店"] {
            let lines = [
                line(name, y: 0.05, height: 0.03),
                line("2026/09/04", y: 0.10),
                line("合計", y: 0.30), price("¥1,000", y: 0.30)
            ]
            let draft = ReceiptParser.parse(lines: lines, now: referenceNow, calendar: calendar)
            XCTAssertEqual(draft.merchant, name)
        }
    }

    /// 住所の行は今までどおり店名にしない。番地の数字が続く形で見分ける。
    func testRealAddressesAreStillRejectedAsShopNames() {
        let lines = [
            line("名古屋市西区平中町352", y: 0.05, height: 0.03),
            line("2026/09/04", y: 0.10),
            line("合計", y: 0.30), price("¥1,000", y: 0.30)
        ]
        let draft = ReceiptParser.parse(lines: lines, now: referenceNow, calendar: calendar)
        XCTAssertNotEqual(draft.merchant, "名古屋市西区平中町352")
    }

    /// 店の案内書きは店名ではない。
    func testOpeningHoursAreNeverTheShopName() {
        let lines = [
            line("営業時間 24時間営業", y: 0.05, height: 0.03),
            line("2026/09/04", y: 0.10),
            line("合計", y: 0.30), price("¥1,000", y: 0.30)
        ]
        let draft = ReceiptParser.parse(lines: lines, now: referenceNow, calendar: calendar)
        XCTAssertNotEqual(draft.merchant, "営業時間 24時間営業")
    }

    /// 有名なお店は店名だけで種類が決まる。
    func testWellKnownEateriesAreDining() {
        for name in ["マクドナルド城町店", "ケンタッキー", "スターバックス", "吉野家", "丸亀製麺"] {
            XCTAssertEqual(ReceiptParser.category(from: "", merchant: name), .dining, name)
        }
    }

    /// 店名で決まらないときは、買ったものの名前で決める。レシート全文より先に見る。
    func testItemNamesDecideTheKindBeforeTheWholeText() {
        let kind = ReceiptParser.category(
            from: "ご来店ありがとうございます 駐車場のご案内",
            merchant: "アイウエオ商会",
            items: [ReceiptItem(name: "ラーメン", amount: 900)]
        )
        XCTAssertEqual(kind, .dining)
    }

    /// スーパーは食費のまま。外食の語を足したせいで動かないこと。
    func testSupermarketsAreStillGroceries() {
        XCTAssertEqual(ReceiptParser.category(from: "", merchant: "スーパーひだまり"), .groceries)
        XCTAssertEqual(ReceiptParser.category(from: "", merchant: "マックスバリュ"), .groceries)
    }
}
