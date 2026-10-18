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
        ReceiptCorpus.tenhou.lines
    }

    /// スーパーのレシート。ロゴが店名で、上部にレジや会計機の記録が並ぶ。
    private func supermarketWithRegisterNumbers() -> [RecognizedLine] {
        ReceiptCorpus.eqvoAugust.lines
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
        let lines = ReceiptCorpus.selfix.lines

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
            line("XXXXXXXXXXXX0000", y: 0.26),
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
        ReceiptCorpus.chavaty.lines
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
        ReceiptCorpus.manaNoMori.lines
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
        ReceiptCorpus.mcdonalds.lines
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

    // MARK: - コノミヤのレシート（実物）

    /// 名古屋のスーパー。読み取りの文字は取れているのに、
    /// **店名「城西店」・金額 25円・種類「その他」** になった。
    ///
    /// 並びは実機が出した読み取り結果そのまま。とくに次の2つが効いている。
    /// - 「合計」の語が読めておらず、金額の行だけが残っている
    /// - 桁区切りのカンマが **ピリオド** として読まれている（`¥3. 374`）
    /// - 店名は上部では「城西店」だけで、チェーン名は**下の広告**にしか出てこない
    private func konomiyaReceipt() -> [RecognizedLine] {
        ReceiptCorpus.konomiya.lines
    }

    func testKonomiyaReceiptReadsTheShopTheAmountAndTheKind() {
        let draft = ReceiptParser.parse(
            lines: konomiyaReceipt(),
            now: date(2026, 8, 10),
            calendar: calendar
        )

        XCTAssertEqual(draft.merchant, "コノミヤ 城西店")
        XCTAssertEqual(draft.amount, 3_374)
        XCTAssertEqual(draft.suggestedCategory, .groceries)
        XCTAssertEqual(draft.date, date(2026, 8, 2))
    }

    /// 桁区切りのカンマがピリオドとして読まれても、1つの金額として扱う。
    /// `¥3. 374` を 3 と 374 に割ると、合計が 3円 になる。
    func testAThousandsCommaReadAsAPeriodIsStillOneAmount() {
        XCTAssertEqual(ReceiptParser.totalAmount(from: ["合計 ¥3. 374"]), 3_374)
        XCTAssertEqual(ReceiptParser.totalAmount(from: ["合計 ¥3.374"]), 3_374)
        XCTAssertEqual(ReceiptParser.totalAmount(from: ["合計 ¥12.345"]), 12_345)
        // 0で始まるように見えるが、整数の側は「10」なのでつなぐ。
        XCTAssertEqual(ReceiptParser.totalAmount(from: ["合計 ¥10.500"]), 10_500)
        // レシートに小数第3位まで刷られることは稀で、桁区切りのほうがずっと多い。
        XCTAssertEqual(ReceiptParser.totalAmount(from: ["合計 ¥1.234"]), 1_234)
    }

    /// 本当の小数はつなげない。
    func testRealDecimalsAreNotJoined() {
        // 給油量。3桁続かないので桁区切りではない。19 も 12 も金額にしない。
        XCTAssertNil(ReceiptParser.totalAmount(from: ["合計 19.12"]))
        // 重さ。金額が0で始まることはないので、これは小数。
        XCTAssertNil(ReceiptParser.totalAmount(from: ["合計 0.398"]))
        XCTAssertNotEqual(ReceiptParser.totalAmount(from: ["数量 19.12"]), 1_912)
        XCTAssertNotEqual(ReceiptParser.totalAmount(from: ["合計 0.398"]), 398)
    }

    /// 税・値引き・点数の行の数字は、合計の候補にしない。
    func testTaxDiscountAndCountRowsAreNeverTheTotal() {
        let lines = [
            line("さくら青果", y: 0.05, height: 0.03),
            line("2026/08/02", y: 0.10),
            line("トマト", y: 0.20), price("¥500", y: 0.20),
            line("値引", y: 0.24), price("-100", y: 0.24),
            line("買上点数", y: 0.28), price("9999点", y: 0.28),
            line("(税率 8%対象額", y: 0.32), price("¥8,888", y: 0.32),
            line("合計", y: 0.40), price("¥400", y: 0.40)
        ]
        let draft = ReceiptParser.parse(lines: lines, now: referenceNow, calendar: calendar)
        XCTAssertEqual(draft.amount, 400)
    }

    /// 上部に支店名しか出ていなくても、チェーン名を落とさない。
    /// レシートのどこかに「チェーン名＋支店名」が刷られていれば、そちらを使う。
    func testAChainNameIsRecoveredFromElsewhereOnTheReceipt() {
        let lines = [
            line("城西店", y: 0.05, height: 0.024),
            line("2026/08/02", y: 0.10),
            line("合計", y: 0.30), price("¥1,000", y: 0.30),
            line("コノミヤ 城西店", y: 0.50, height: 0.030),
            line("スタッフ募集中！", y: 0.54, height: 0.030)
        ]
        let draft = ReceiptParser.parse(lines: lines, now: referenceNow, calendar: calendar)
        XCTAssertEqual(draft.merchant, "コノミヤ 城西店")
    }

    /// 求人の広告は店名ではない。
    func testStaffWantedAdvertsAreNotTheShopName() {
        for text in ["スタッフ募集中！", "従業員割引有り", "ご応募お待ちしています"] {
            let lines = [
                line(text, y: 0.05, height: 0.03),
                line("2026/08/02", y: 0.10),
                line("合計", y: 0.30), price("¥1,000", y: 0.30)
            ]
            let draft = ReceiptParser.parse(lines: lines, now: referenceNow, calendar: calendar)
            XCTAssertNotEqual(draft.merchant, text)
        }
    }

    /// 食料品の名前が並んでいれば食費。店名で決まらないときの二段目。
    func testGroceryItemsDecideTheKindWhenTheShopIsUnknown() {
        let kind = ReceiptParser.category(
            from: "",
            merchant: "アイウエオ商会",
            items: [
                ReceiptItem(name: "ぶなしめじ", amount: 98),
                ReceiptItem(name: "株水おいしい牛乳", amount: 188),
                ReceiptItem(name: "フィリピ ンバナナ", amount: 158)
            ]
        )
        XCTAssertEqual(kind, .groceries)
    }

    // MARK: - イオンスタイルのレシート（実物）

    /// 名古屋のイオンスタイルで撮った1枚。
    ///
    /// 画面に出た金額は **47088**。レシートのどこにも無い額に見えるが、
    /// クレジット売上票の **「カード会社 VISA JAPAN 47088」** の番号だった。
    ///
    /// このレシートには2つの罠がある。
    /// 1. 合計が **「合　計」** と字の間を空けて刷られていて、`contains("合計")` が外れる
    /// 2. 明細に通貨の印が無く（`398※`）、下半分が売上票の数字だらけ
    private func aeonReceipt() -> [RecognizedLine] {
        ReceiptCorpus.aeonSeptember.lines
    }

    /// 実機で 47088 になった1枚。合計 3,826円 が出ること。
    func testAeonReceiptReadsTheTotalAndNotTheCardCompanyNumber() {
        let draft = ReceiptParser.parse(
            lines: aeonReceipt(),
            now: date(2026, 9, 26),
            calendar: calendar
        )

        XCTAssertEqual(draft.amount, 3_826)
        XCTAssertEqual(draft.date, date(2026, 9, 21))
        XCTAssertEqual(draft.suggestedCategory, .groceries)
        XCTAssertTrue(draft.merchant.contains("AEON") || draft.merchant.contains("イオン"),
                      "店名が「\(draft.merchant)」になった")
    }

    /// 47088 は候補として残ってもよいが、選ばれてはいけない。
    /// 「候補から消す」ではなく「点数で負ける」ことを確かめる。
    func testTheCardCompanyNumberLosesToTheTotal() {
        let rows = ReceiptParser.rows(from: aeonReceipt())
        let candidates = ReceiptParser.totalCandidates(in: rows, itemsTotal: 4_831)
        let cardNumber = candidates.filter { $0.amount == 47_088 }
        let total = candidates.filter { $0.amount == 3_826 }

        XCTAssertFalse(total.isEmpty, "3,826 が候補に入っていない")
        for slip in cardNumber {
            for real in total {
                XCTAssertLessThan(slip.score, real.score,
                                  "47088(\(slip.score)) が 3826(\(real.score)) に勝っている")
            }
        }
    }

    /// 字の間が空いていても合計の語として通ること。
    /// イオンは「合　計」、他店でも「お 買 上」のように空けて刷ることがある。
    func testATotalKeywordSurvivesSpacesBetweenItsCharacters() {
        for spelling in ["合計", "合　計", "合 計", "お　買　上", "ご 請 求"] {
            let lines = [
                line("スーパーどこか", y: 0.05, height: 0.03),
                line("2026/09/21", y: 0.10),
                line("りんご", y: 0.20), price("300", y: 0.20),
                line("みかん", y: 0.24), price("400", y: 0.24),
                line("ぶどう", y: 0.28), price("250", y: 0.28),
                line("もも", y: 0.32), price("284", y: 0.32),
                line(spelling, y: 0.40), price("¥1,234", y: 0.40),
                line("カード会社 VISA JAPAN 47088", y: 0.70)
            ]
            let draft = ReceiptParser.parse(lines: lines, now: referenceNow, calendar: calendar)
            XCTAssertEqual(draft.amount, 1_234, "「\(spelling)」で合計を見失った")
        }
    }

    /// 明細が数件しか読めていないときは、上側の判定をしない。
    ///
    /// **20品のレシートで2品しか読めなければ、和は実際の1割ということもある。**
    /// その和を basis に「大きすぎる」と切ると、正しい合計まで落としてしまう。
    func testTheUpperBoundNeedsEnoughItemsToMeanAnything() {
        let rows = ReceiptParser.rows(from: [
            line("合計", y: 0.50), price("¥9,800", y: 0.50)
        ])
        let fewItems = ReceiptParser.totalCandidates(in: rows, itemsTotal: 300, itemsCount: 1)
        let manyItems = ReceiptParser.totalCandidates(in: rows, itemsTotal: 300, itemsCount: 8)

        XCTAssertGreaterThan(fewItems.first?.score ?? 0, manyItems.first?.score ?? 0)
        XCTAssertGreaterThan(fewItems.first?.score ?? 0, 0, "明細1件を根拠に合計を落としている")
    }

    /// 明細の和より桁がひとつ大きい候補は落とす。
    /// 下側（6割を切る）だけ見ていたので、売上票の番号が素通りしていた。
    func testACandidateFarAboveTheItemsTotalIsRejected() {
        let rows = ReceiptParser.rows(from: [
            line("りんご", y: 0.20), price("300", y: 0.20),
            line("みかん", y: 0.25), price("200", y: 0.25),
            line("端末 47088", y: 0.60)
        ])
        let candidates = ReceiptParser.totalCandidates(in: rows, itemsTotal: 500)
        let big = candidates.first { $0.amount == 47_088 }
        XCTAssertNotNil(big)
        XCTAssertLessThan(big?.score ?? 0, 0, "明細の和の90倍が減点されていない")
    }

    /// 明細を上限まで拾って打ち切ったときは、上側を見ない。
    /// 和が「途中まで」の値なので、本当の合計はいくらでも大きくなりうる。
    func testTheUpperBoundIsIgnoredWhenTheItemListWasCutOff() {
        let rows = ReceiptParser.rows(from: [
            line("合計", y: 0.50), price("¥90,000", y: 0.50)
        ])
        let capped = ReceiptParser.totalCandidates(in: rows, itemsTotal: 1_000, itemsCapped: true)
        let notCapped = ReceiptParser.totalCandidates(in: rows, itemsTotal: 1_000, itemsCapped: false)
        XCTAssertGreaterThan(capped.first?.score ?? 0, notCapped.first?.score ?? 0)
    }

    // MARK: - EQVo!（エクポスタイル）のレシート（実物）

    /// 同じ日に撮ったもう1枚。こちらは 6,088円 と正しく読めていた。
    /// イオンの直しで**壊れていないこと**を確かめるために置く。
    private func eqvoReceipt() -> [RecognizedLine] {
        ReceiptCorpus.eqvoSeptember.lines
    }

    /// すでに正しく読めている1枚。イオンの直しで壊していないこと。
    func testEqvoReceiptStillReadsSixThousandAndEightyEight() {
        let draft = ReceiptParser.parse(
            lines: eqvoReceipt(),
            now: date(2026, 9, 26),
            calendar: calendar
        )

        XCTAssertEqual(draft.amount, 6_088)
        XCTAssertEqual(draft.date, date(2026, 9, 23))
        XCTAssertEqual(draft.suggestedCategory, .groceries)
    }

    // MARK: - Eggs 'n Things 名古屋PARCO店（2026-10-04 実機）

    /// 実機で読み取った1枚。**店名が崩れ、種類が「その他」になった。**
    ///
    /// 店名は読み取りそのものが外している（`Eggs'` → `R`、`PARCO` → `PARC0`）。
    /// そこは直せないが、**飲食店の伝票だと分かる手がかりは本文に残っている。**
    /// 金額と日付は最初から正しく読めていた。
    private func eggsNThingsReceipt() -> [RecognizedLine] {
        [
            // ロゴは筆記体で、文字としてはほとんど読めない。
            line("Eggs'n Things", y: 0.030, height: 0.034),
            line("Hawaii", y: 0.050),
            line("Established in 1974", y: 0.062),
            // 実機がここをこう読んだ。テストでも同じ崩れ方を入れておく。
            line("「R Things名古屋PARC0店", y: 0.082, height: 0.022),
            line("愛知県名古屋市中区栄3-29-11", y: 0.096),
            line("名古屋PARCO midi", y: 0.108),
            line("TEL 052-241-6565", y: 0.120),
            line("店No-0000000000010-0001", y: 0.132),
            line("2026/10/04 （日） 12:02", y: 0.146),
            line("伝票No-00216", y: 0.158),
            line("テーブル１０１", y: 0.170),
            line("2名", y: 0.186),
            line("EAT-IN", y: 0.200),

            line("ベネディクトサーモン", y: 0.220), price("¥1,826", y: 0.220),
            line("マッシュポテト", y: 0.234), price("¥0", y: 0.234),
            line("セットパイナップルパンケーキ", y: 0.248), price("¥638", y: 0.248),
            line("ロコモコ", y: 0.268), price("¥1,485", y: 0.268),
            line("アイスコーヒー", y: 0.282), price("¥660", y: 0.282),
            line("マンゴーパッションフルーツレモネード", y: 0.296), price("¥693", y: 0.296),

            line("合計 6点", y: 0.330, height: 0.026), price("¥5,302", y: 0.330),
            line("（内消費税等", y: 0.346), price("¥482）", y: 0.346),
            line("10%対象", y: 0.358), price("¥5,302", y: 0.358),
            line("（標準税率", y: 0.370), price("¥482）", y: 0.370),
            line("クレジット", y: 0.384),
            line("1", y: 0.398), price("¥5,302", y: 0.398),

            line("EGGS' N THINGS JAPAN株式会社", y: 0.430),
            line("登録番号 T6011001062650", y: 0.444),
            line("会計担当 A", y: 0.458),
            line("No0109531", y: 0.470)
        ]
    }

    /// 金額と日付。ここは実機でも最初から合っていた。壊さないための押さえ。
    func testEggsNThingsReceiptReadsFiveThousandThreeHundredAndTwo() {
        let draft = ReceiptParser.parse(
            lines: eggsNThingsReceipt(),
            now: date(2026, 10, 5),
            calendar: calendar
        )

        XCTAssertEqual(draft.amount, 5_302)
        XCTAssertEqual(draft.date, date(2026, 10, 4))
    }

    /// **実機で外したのはここ。** 種類が「その他」になっていた。
    ///
    /// 店名が崩れているので店名からは何も分からず、品名も
    /// 「ロコモコ」「アイスコーヒー」のようにスーパーでも買えるものばかり。
    /// 残る手がかりは `EAT-IN` のような、**飲食店の伝票にしか出ない語**だけ。
    func testARestaurantBillIsDiningEvenWhenTheShopNameIsMisread() {
        let draft = ReceiptParser.parse(
            lines: eggsNThingsReceipt(),
            now: date(2026, 10, 5),
            calendar: calendar
        )

        XCTAssertEqual(draft.suggestedCategory, .dining)
    }

    /// **「テーブル」を外食の語にしてはいけない。**
    ///
    /// EQVo! の店名は「ファミリーテーブル」で、これはスーパー。
    /// 便利そうに見える語を足すと、こういう1枚が黙って外食に化ける。
    func testATableInTheShopNameDoesNotMakeItDining() {
        XCTAssertNotEqual(
            ReceiptParser.category(from: "", merchant: "EQVo! ファミリーテーブル"),
            .dining
        )
    }

    /// ローマ字の「AEON」でも食費と分かること。
    /// カタカナの「イオン」しか見ていないと、店名からは何も分からなかった。
    func testAeonInRomanLettersIsGroceries() {
        XCTAssertEqual(
            ReceiptParser.category(from: "", merchant: "AEON STYLE"),
            .groceries
        )
    }

    // MARK: - 富士サファリパーク テイクアウトフード（2026-10-13 実機）

    /// 実機で読み取った1枚。**種類が「その他」になった。**
    ///
    /// 店名は「領収算書」の朱印を崩し字のまま拾っていて（実機では「漬汁算素」）、
    /// そこは読み取りそのものが外しているので直せない。
    /// 品名も「モンブランソフト」「フルーツソーダ」で、スーパーの菓子売り場にもある。
    /// **残っていた手がかりは、店名の行に並んだ「テイクアウトフード」だけ。**
    ///
    /// 金額と日付は最初から正しく読めていた。
    ///
    /// 並びは実機の画面に出た読み取り結果と、レシートに見える行から組み直したもので、
    /// 1文字ずつの写しではない。品の値段は合計と足し算が合う（750 + 600 = 1,350）。
    private func fujiSafariReceipt() -> [RecognizedLine] {
        [
            // 朱印。いちばん大きいので、店名はここから取られてしまう。
            line("漬汁算素", y: 0.028, height: 0.040),
            line("富士サファリパーク テイクアウトフード", y: 0.058, height: 0.020),
            line("〒410-1231 静岡県裾野市須山2255-27", y: 0.072),
            line("TEL 055-998-1311", y: 0.084),
            line("2026年10月12日(月) 14:30", y: 0.100),
            line("No.0007653", y: 0.112),

            line("モンブランソフト 和栗", y: 0.140), price("¥750", y: 0.140),
            line("フルーツソーダ ストロベリー", y: 0.154), price("¥600", y: 0.154),

            line("合計 2点", y: 0.186, height: 0.026), price("¥1,350", y: 0.186),
            line("8%対象", y: 0.202), price("¥1,350", y: 0.202),
            line("(内消費税等", y: 0.214), price("¥100)", y: 0.214),
            line("クレジット", y: 0.230), price("¥1,350", y: 0.230),

            line("登録番号 T6010001139401", y: 0.260)
        ]
    }

    /// 金額と日付。ここは実機でも最初から合っていた。壊さないための押さえ。
    func testFujiSafariReceiptReadsOneThousandThreeHundredAndFifty() {
        let draft = ReceiptParser.parse(
            lines: fujiSafariReceipt(),
            now: date(2026, 10, 13),
            calendar: calendar
        )

        XCTAssertEqual(draft.amount, 1_350)
        XCTAssertEqual(draft.date, date(2026, 10, 12))
    }

    /// **実機で外したのはここ。** 種類が「その他」になっていた。
    ///
    /// 店名が崩し字で読めず、品名もスーパーで買えるものばかり。
    /// 「テイクアウト」は売店の伝票にしか出ない語なので、最後の手がかりとして効く。
    func testATakeawayFoodStallIsDiningEvenWhenTheShopNameIsUnreadable() {
        let draft = ReceiptParser.parse(
            lines: fujiSafariReceipt(),
            now: date(2026, 10, 13),
            calendar: calendar
        )

        XCTAssertEqual(draft.suggestedCategory, .dining)
    }

    // MARK: - ミスタードーナツ mozoワンダーシティショップ（2026-10-13 実機）

    /// 実機で読み取った1枚。**種類が「水道・光熱」になった。**
    ///
    /// このレシートは品名と値段が別の行に分かれて印字されている。
    /// 値段の側の行が「1点※」なので、**店名がその「1点」になった。**
    /// 店名からも品名からも何も分からず、本文まで落ちたところで
    /// 裏書きの「クーポンは携帯・スマホ専用です」の**「携帯」**が引っかかり、
    /// ドーナツ代が光熱費になった。
    ///
    /// 金額と日付は最初から正しく読めていた。
    ///
    /// 並びは実機の画面に出た読み取り結果と、レシートに見える行から組み直したもので、
    /// 1文字ずつの写しではない。品の値段は合計と足し算が合う
    /// （270 + 183 + 226 + 205 = 884）。
    private func misterDonutReceipt() -> [RecognizedLine] {
        [
            line("mister Donut", y: 0.030, height: 0.030),
            line("No. 1914", y: 0.048),
            line("mozoワンダーシティショップ", y: 0.062),
            line("電話052-501-2661", y: 0.074),
            line("2026年10月04日(日) 17時40分", y: 0.090),

            // 品名の行に値段が無く、次の行の「1点※」に値段が付く。
            // 店名がここから取られた。
            line("サクッと香る煮込みトマチキパイ", y: 0.118),
            line("1点※", y: 0.130, height: 0.022), price("¥270", y: 0.130),
            line("オールドファッション", y: 0.146),
            line("1点※", y: 0.158, height: 0.022), price("¥183", y: 0.158),
            line("ポン・デ・ザクショコラ", y: 0.174),
            line("1点※", y: 0.186, height: 0.022), price("¥226", y: 0.186),
            line("ポン・デ・ダブルショコラ", y: 0.202),
            line("1点※", y: 0.214, height: 0.022), price("¥205", y: 0.214),

            line("合計 4点", y: 0.246, height: 0.026), price("¥884", y: 0.246),
            line("(10%対象", y: 0.262), price("¥0)", y: 0.262),
            line("( 8%対象", y: 0.274), price("¥819)", y: 0.274),
            line("(内消費税等", y: 0.286), price("¥65)", y: 0.286),
            line("クレジット", y: 0.302), price("¥884", y: 0.302),

            line("※は軽減税率対象商品です", y: 0.330),
            line("登録番号 T5180001037671", y: 0.344),

            // 裏書き。ここが種類を決めてしまっていた。
            line("クーポンは携帯・スマホ専用です", y: 0.372),
            line("全国のミスタードーナツでご利用いただけます", y: 0.386)
        ]
    }

    /// 金額と日付。ここは実機でも最初から合っていた。壊さないための押さえ。
    func testMisterDonutReceiptReadsEightHundredAndEightyFour() {
        let draft = ReceiptParser.parse(
            lines: misterDonutReceipt(),
            now: date(2026, 10, 13),
            calendar: calendar
        )

        XCTAssertEqual(draft.amount, 884)
        XCTAssertEqual(draft.date, date(2026, 10, 4))
    }

    /// **実機で外したのはここ。** 種類が「水道・光熱」になっていた。
    ///
    /// 店名が「1点」で、品名も「1点※」。本文の店名だけが残る手がかり。
    func testMisterDonutIsDiningEvenWhenTheShopNameIsAQuantity() {
        let draft = ReceiptParser.parse(
            lines: misterDonutReceipt(),
            now: date(2026, 10, 13),
            calendar: calendar
        )

        XCTAssertEqual(draft.suggestedCategory, .dining)
    }

    // MARK: - 短い一般語を水道・光熱に置かないこと

    /// **「携帯」を水道・光熱の語にしてはいけない。**
    ///
    /// クーポンやアンケートの注意書きに必ず出る語で、レシートの中身とは関係がない。
    /// これだけでミスタードーナツのレシートが光熱費になった。
    func testACouponAboutMobilePhonesIsNotAUtilityBill() {
        XCTAssertNotEqual(
            ReceiptParser.category(from: "クーポンは携帯・スマホ専用です"),
            .utilities
        )
    }

    /// **「ガス」を水道・光熱の語にしてはいけない。**
    ///
    /// 「ガスト」に「ガス」が入っている。水道・光熱は外食より前に並んでいるので、
    /// 1件ずつの同点では水道・光熱が勝ち（`bestMatch` は `hits > best?.hits`）、
    /// ファミレスの代金が光熱費になる。
    func testGustoIsDiningAndNotAUtilityBill() {
        XCTAssertEqual(
            ReceiptParser.category(from: "", merchant: "ガスト 名古屋栄店"),
            .dining
        )
    }

    /// 短い語を外した代わりに、公共料金そのものは取り逃がさないこと。
    /// 「東京電力」に「電気」は入っていない（「電力」）ので、両方を見る。
    func testRealUtilityBillsAreStillUtilities() {
        XCTAssertEqual(
            ReceiptParser.category(from: "", merchant: "東京電力エナジーパートナー"),
            .utilities
        )
        XCTAssertEqual(
            ReceiptParser.category(from: "", merchant: "東京ガス 都市ガス料金"),
            .utilities
        )
        XCTAssertEqual(
            ReceiptParser.category(from: "", merchant: "ソフトバンク"),
            .utilities
        )
        XCTAssertEqual(
            ReceiptParser.category(from: "", merchant: "名古屋市上下水道局 水道料金"),
            .utilities
        )
    }
}
