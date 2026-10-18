import XCTest
@testable import FutariKakeibo

/// レシート読み取りの第2段階: 店と品の辞書、品名と値段が別の行の品、品ごとの種類。
///
/// ここは**作った例**（回帰テスト）。実物のレシートでの正解率は `ZReceiptScoreboardTests` で数える。
final class ReceiptDictionaryTests: XCTestCase {
    private let calendar = ReceiptCorpus.calendar
    private let now = ReceiptCorpus.day(2026, 10, 18)
    private let dictionary = ReceiptDictionary.bundled

    private func line(
        _ text: String,
        x: Double = 0.08,
        width: Double = 0.5,
        y: Double,
        height: Double = 0.018,
        alternatives: [String] = []
    ) -> RecognizedLine {
        RecognizedLine(text: text, minX: x, maxX: x + width, midY: y, height: height, alternatives: alternatives)
    }

    private func price(_ text: String, y: Double) -> RecognizedLine {
        RecognizedLine(text: text, minX: 0.74, maxX: 0.93, midY: y, height: 0.018)
    }

    private func parse(_ lines: [RecognizedLine]) -> ReceiptDraft {
        ReceiptParser.parse(lines: lines, now: now, calendar: calendar)
    }

    // MARK: - 辞書そのもの

    /// アプリに同梱した辞書が読めること。読めないと辞書なしの読み方に戻るだけで気づきにくい。
    func testTheBundledDictionaryLoads() {
        XCTAssertGreaterThanOrEqual(dictionary.chains.count, 50)
        XCTAssertFalse(dictionary.productNames.isEmpty)
        XCTAssertFalse(dictionary.productCategories.isEmpty)
        XCTAssertTrue(dictionary.chains.contains { $0.name == "マクドナルド" && $0.category == .dining })
    }

    /// 種類の名前を書き間違えた1件は捨て、ほかは読む。
    func testAnEntryWithAnUnknownCategoryIsSkipped() throws {
        let json = """
        {"chains": [
          {"name": "よい店", "aliases": ["よい店"], "category": "groceries"},
          {"name": "まちがい", "aliases": ["まちがい"], "category": "grocery"}
        ], "productNames": [], "productCategories": {}}
        """
        let decoded = try XCTUnwrap(ReceiptDictionary.decode(Data(json.utf8)))
        XCTAssertEqual(decoded.chains.map(\.name), ["よい店"])
    }

    // MARK: - 店名

    /// ロゴの「AEON STYLE」より、本文の「イオンスタイルワンダーシティ」を店名にする。
    func testTheBranchPrintedNextToTheChainNameIsUsed() {
        let rows = ReceiptParser.rows(from: [
            line("AEON STYLE", y: 0.03, height: 0.03),
            line("イオンスタイルワンダーシティ", y: 0.05),
            line("TEL052-506-5600", y: 0.07),
            line("イオンリテール株式会社", y: 0.09)
        ])
        let found = ReceiptParser.chainMerchant(in: rows, dictionary: dictionary)
        XCTAssertEqual(found?.name, "イオンスタイルワンダーシティ")
        XCTAssertEqual(found?.chain.category, .groceries)
    }

    /// チェーン名だけの行と、支店名だけの行を組み合わせる。
    func testAChainNameAndASeparateBranchLineAreCombined() {
        let rows = ReceiptParser.rows(from: [
            line("mister Donut", y: 0.03, height: 0.03),
            line("No. 1914", y: 0.05),
            line("mozoワンダーシティショップ", y: 0.07)
        ])
        XCTAssertEqual(
            ReceiptParser.chainMerchant(in: rows, dictionary: dictionary)?.name,
            "ミスタードーナツ mozoワンダーシティショップ"
        )
    }

    /// 1文字の読み違い（「エクポ」）でもチェーンと分かり、正しい名前で出す。
    func testAOneCharacterMisreadStillFindsTheChain() {
        let rows = ReceiptParser.rows(from: [
            line("EQVo! エクポスタイル", y: 0.05, height: 0.03),
            line("052-503-2116", y: 0.08)
        ])
        XCTAssertEqual(ReceiptParser.chainMerchant(in: rows, dictionary: dictionary)?.name, "EQVo! エクボスタイル")
    }

    /// 会社名の行でチェーンが分かり、支店名は上の行から取る。支店名の頭の読み違いのかけらは落とす。
    func testTheCompanyLineIdentifiesTheChainAndTheBranchComesFromTheTop() {
        let rows = ReceiptParser.rows(from: [
            line("Eggs'", y: 0.05),
            line("2 Things名古屋PARC0店", y: 0.07),
            line("愛知県名古屋市中区栄3-29-11", y: 0.09),
            line("ロコモコ", y: 0.20), price("¥1,485", y: 0.20),
            line("EGOS' N THINGS JAPAN株式会社", y: 0.40)
        ])
        XCTAssertEqual(
            ReceiptParser.chainMerchant(in: rows, dictionary: dictionary)?.name,
            "Eggs 'n Things 名古屋PARCO店"
        )
    }

    /// 名前を1文字読み違えた行は、辞書の名前に直して支店名を付ける。
    func testAMisreadChainNameIsCorrectedAndKeepsItsBranch() {
        let rows = ReceiptParser.rows(from: [line("マクドナルト城町店", y: 0.05, height: 0.03)])
        XCTAssertEqual(ReceiptParser.chainMerchant(in: rows, dictionary: dictionary)?.name, "マクドナルド城町店")
    }

    /// 品名に店の名前が入っていても、店と取り違えない（値段の付いた行は見ない）。
    func testAProductNameContainingAChainNameIsNotTheShop() {
        let rows = ReceiptParser.rows(from: [
            line("どこかの薬局", y: 0.05, height: 0.03),
            line("イオン飲料", y: 0.20), price("¥158", y: 0.20)
        ])
        XCTAssertNil(ReceiptParser.chainMerchant(in: rows, dictionary: dictionary))
    }

    /// 下のほうの案内書きに出てくるチェーン名では、店を決めない。
    func testAChainMentionedInAFooterDoesNotDecideTheShop() {
        var lines = [line("あおぞら商店", y: 0.03, height: 0.03)]
        for index in 0..<12 {
            lines.append(line("品\(index)", y: 0.06 + Double(index) * 0.02))
            lines.append(price("¥100", y: 0.06 + Double(index) * 0.02))
        }
        lines.append(line("ローソンでもご利用いただけます", y: 0.40))
        let rows = ReceiptParser.rows(from: lines)
        XCTAssertNil(ReceiptParser.chainMerchant(in: rows, dictionary: dictionary))
    }

    /// 読み取りの2番目の読み方でチェーン名が合えば、それを使う。
    func testAnAlternativeReadingCanIdentifyTheChain() {
        let rows = ReceiptParser.rows(from: [
            line("マクドナノレド城町店", y: 0.05, height: 0.03, alternatives: ["マクドナルド城町店"])
        ])
        XCTAssertEqual(ReceiptParser.chainMerchant(in: rows, dictionary: dictionary)?.name, "マクドナルド城町店")
    }

    // MARK: - 品名

    /// 辞書にある略し方は正式な名前を添える。読み取った表記は残す。
    func testAKnownAbbreviationGetsItsFullName() {
        let items = ReceiptParser.annotated(
            [ReceiptItem(name: "キヌトウフ", amount: 58), ReceiptItem(name: "国産ブタコマ", amount: 398)],
            dictionary: dictionary
        )
        XCTAssertEqual(items.map(\.name), ["キヌトウフ", "国産ブタコマ"])
        XCTAssertEqual(items.map(\.normalizedName), ["絹ごし豆腐", "豚こま切れ肉"])
        XCTAssertEqual(items.map(\.category), [.groceries, .groceries])
    }

    /// 辞書に無い表記は、もっともらしい名前を作らずにそのまま。
    func testAnUnknownAbbreviationIsLeftAsRead() {
        let items = ReceiptParser.annotated([ReceiptItem(name: "ボールドJ", amount: 498)], dictionary: dictionary)
        XCTAssertNil(items.first?.normalizedName)
        XCTAssertEqual(items.first?.name, "ボールドJ")
        XCTAssertEqual(items.first?.category, .household, "ボールドは衣料用洗剤の名前なので日用品の候補")
    }

    // MARK: - 品名と値段が別の行

    /// 長い品名の値段が次の行に回る（Eggs 'n Things）。すぐ上の品名と組にする。
    func testAPriceOnItsOwnLineGoesWithTheNameJustAbove() {
        let draft = parse([
            line("どこかの食堂", y: 0.03, height: 0.03),
            line("TEL 03-0000-0000", y: 0.06),
            line("2026/10/18 12:00", y: 0.09),
            line("EAT-IN", y: 0.12),
            line("ベネディクトサーモン", y: 0.16), price("¥1,826", y: 0.16),
            line("マッシュポテト", y: 0.19),
            line("セットパイナップルパンケーキ", y: 0.22),
            price("¥638", y: 0.25),
            line("合計 3点", y: 0.30), price("¥2,464", y: 0.30)
        ])
        XCTAssertEqual(draft.items.map(\.name), ["ベネディクトサーモン", "セットパイナップルパンケーキ"])
        XCTAssertEqual(draft.items.map(\.amount), [1_826, 638])
    }

    /// 商品コードと値段の行の下に品名が来る（ガソリンスタンド）。
    func testAPriceAboveTheNameGoesWithTheNameBelow() {
        let draft = parse(ReceiptCorpus.selfix.lines)
        XCTAssertEqual(draft.items.count, 1)
        XCTAssertEqual(draft.items.first?.amount, 2_964)
        XCTAssertTrue(draft.items.first?.name.contains("レギュラーガソリン") == true)
    }

    // MARK: - 種類（品ごとの種類を値段の重さで）

    /// ドラッグストアでも、食べ物が大半なら食費。
    func testADrugstoreReceiptMostlyFoodIsGroceries() {
        let decided = ReceiptParser.receiptCategory(
            text: "",
            merchant: "スギ薬局 どこか店",
            items: ReceiptParser.annotated([
                ReceiptItem(name: "牛乳", amount: 198),
                ReceiptItem(name: "食パン", amount: 158),
                ReceiptItem(name: "たまご", amount: 248),
                ReceiptItem(name: "目薬", amount: 98)
            ], dictionary: dictionary),
            chain: dictionary.chains.first { $0.name == "スギ薬局" }
        )
        XCTAssertEqual(decided.category, .groceries)
    }

    /// スーパーでも、洗剤が大半なら日用品。
    func testASupermarketReceiptMostlyDetergentIsHousehold() {
        let decided = ReceiptParser.receiptCategory(
            text: "",
            merchant: "バロー どこか店",
            items: ReceiptParser.annotated([
                ReceiptItem(name: "アタック 詰替", amount: 598),
                ReceiptItem(name: "キッチンペーパー", amount: 298),
                ReceiptItem(name: "牛乳", amount: 198)
            ], dictionary: dictionary),
            chain: dictionary.chains.first { $0.name == "バロー" }
        )
        XCTAssertEqual(decided.category, .household)
    }

    /// 飲食店は、品がスーパーにある名前でも外食。
    func testARestaurantStaysDiningWhateverTheItems() {
        let decided = ReceiptParser.receiptCategory(
            text: "",
            merchant: "マクドナルド 城町店",
            items: ReceiptParser.annotated([ReceiptItem(name: "牛乳", amount: 150)], dictionary: dictionary),
            chain: dictionary.chains.first { $0.name == "マクドナルド" }
        )
        XCTAssertEqual(decided.category, .dining)
        XCTAssertTrue(decided.wellEvidenced)
    }

    // MARK: - AIの答え

    /// 辞書で店が決まっているときは、AIの店名と種類で上書きしない。
    func testAnAIAnswerDoesNotOverrideAShopFoundInTheDictionary() {
        let base = ReceiptDraft(
            merchant: "マクドナルド 城町店",
            suggestedCategory: .dining,
            merchantIsWellEvidenced: true,
            categoryIsWellEvidenced: true
        )
        let answer = ReceiptAnswer(date: "", merchant: "城町", total: nil, category: "utilities")
        let merged = ReceiptInterpreter.merged(base: base, answer: answer, now: now, calendar: calendar)
        XCTAssertEqual(merged.merchant, "マクドナルド 城町店")
        XCTAssertEqual(merged.suggestedCategory, .dining)
    }
}
