import XCTest
@testable import FutariKakeibo

/// 一度直した店を覚えて、次から使う仕組み。
final class MerchantMemoTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    // MARK: - 同じ店だと見分ける鍵

    /// 電話番号があれば、それを鍵にする。店ごとに違い、店名の読み違いに影響されない。
    ///
    /// 2026-10 までは登録番号を先にしていた。**登録番号は事業者ごとの番号で、支店を見分けない**
    /// （イオンリテールは全国の店が同じ番号）。利用者の指示で順番を入れ替えた。
    func testPhoneNumberIsPreferredBecauseTheInvoiceNumberIsPerCompany() {
        let key = MerchantKey.make(
            fromReceiptText: """
            写北名古屋
            愛知県北名古屋市鹿田東村79
            TEL:0568-54-1790
            登録番号：T2170001007389
            """,
            merchant: "写北名古屋"
        )
        XCTAssertEqual(key, "tel:0568541790")
    }

    /// 同じ店なら、店名の読み違いが違っても同じ鍵になる。ここが仕組みの要。
    func testSameShopGivesTheSameKeyDespiteMisreadName() {
        let first = MerchantKey.make(
            fromReceiptText: "写北名古屋\nTEL:0568-54-1790\n登録番号：T2170001007389",
            merchant: "写北名古屋"
        )
        let second = MerchantKey.make(
            fromReceiptText: "Selfix北名古屋\nTEL:0568-54-1790\n登録番号:T2170001007389",
            merchant: "Selfix北名古屋"
        )
        XCTAssertEqual(first, second)
    }

    /// 電話が読めず登録番号だけのときは、事業者の鍵は同じでも、店の鍵には店名が入る。
    /// 登録番号だけで「同じ店」と決めないため。
    func testAnInvoiceNumberAloneOnlyIdentifiesTheCompany() {
        let first = "写北名古屋\n登録番号：T2170001007389"
        let second = "Selfix北名古屋\n登録番号:T2170001007389"
        XCTAssertEqual(
            MerchantKey.businessKey(fromReceiptText: first),
            MerchantKey.businessKey(fromReceiptText: second)
        )
        XCTAssertEqual(MerchantKey.businessKey(fromReceiptText: first), "invoice:2170001007389")
        XCTAssertEqual(
            MerchantKey.make(fromReceiptText: first, merchant: "写北名古屋"),
            "invoice:2170001007389|写北名古屋"
        )
    }

    /// 登録番号が読めなくても電話番号があればよい。
    func testPhoneNumberIsTheSecondChoice() {
        let key = MerchantKey.make(
            fromReceiptText: "あおぞら商店\nTEL:0568-54-1790",
            merchant: "あおぞら商店"
        )
        XCTAssertEqual(key, "tel:0568541790")
    }

    /// どちらも無ければ店名。空白と記号の違いでは別の店にしない。
    func testFallsBackToTheNameIgnoringSpacingAndSymbols() {
        let first = MerchantKey.make(fromReceiptText: "あおぞら商店", merchant: "あおぞら商店")
        let second = MerchantKey.make(fromReceiptText: "あおぞら 商店", merchant: "あおぞら 商店")
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, "name:あおぞら商店")
    }

    func testNoKeyWhenNothingIsReadable() {
        XCTAssertNil(MerchantKey.make(fromReceiptText: "", merchant: ""))
    }

    // MARK: - 覚えて使う

    func testRememberedShopReplacesTheGuess() {
        let memos = [
            MerchantMemo(
                key: "invoice:2170001007389",
                merchant: "Selfix北名古屋",
                category: .transportation,
                updatedAt: now
            )
        ]
        let draft = ReceiptDraft(
            merchant: "写北名古屋",
            amount: 2_964,
            suggestedCategory: .other,
            shopKey: "invoice:2170001007389"
        )

        let applied = MerchantMemory.applying(memos, to: draft)
        XCTAssertEqual(applied.merchant, "Selfix北名古屋")
        XCTAssertEqual(applied.suggestedCategory, .transportation)
        XCTAssertTrue(applied.usedMemo)
        // 金額は覚えない。毎回違うため。
        XCTAssertEqual(applied.amount, 2_964)
    }

    func testUnknownShopIsLeftAlone() {
        let memos = [
            MerchantMemo(key: "invoice:1", merchant: "覚えた店", category: .dining, updatedAt: now)
        ]
        let draft = ReceiptDraft(
            merchant: "はじめての店",
            suggestedCategory: .groceries,
            shopKey: "invoice:2"
        )

        let applied = MerchantMemory.applying(memos, to: draft)
        XCTAssertEqual(applied.merchant, "はじめての店")
        XCTAssertEqual(applied.suggestedCategory, .groceries)
        XCTAssertFalse(applied.usedMemo)
    }

    func testRememberingAddsTheShop() {
        let memos = MerchantMemory.remembering(
            [], key: "invoice:1", merchant: "Selfix北名古屋",
            category: .transportation, now: now
        )
        XCTAssertEqual(memos.count, 1)
        XCTAssertEqual(memos.first?.merchant, "Selfix北名古屋")
    }

    /// 一度間違って覚えても、直して保存すれば上書きできる。
    func testRememberingOverwritesTheSameShop() {
        let first = MerchantMemory.remembering(
            [], key: "invoice:1", merchant: "まちがった名前",
            category: .other, now: now
        )
        let second = MerchantMemory.remembering(
            first, key: "invoice:1", merchant: "ただしい名前",
            category: .groceries, now: now.addingTimeInterval(60)
        )

        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.merchant, "ただしい名前")
        XCTAssertEqual(second.first?.category, .groceries)
    }

    func testBlankNameIsNotRemembered() {
        let memos = MerchantMemory.remembering(
            [], key: "invoice:1", merchant: "   ", category: .other, now: now
        )
        XCTAssertTrue(memos.isEmpty)
    }

    /// 上限を超えたら、長く使っていないものから捨てる。
    func testOldestAreDroppedPastTheLimit() {
        var memos: [MerchantMemo] = []
        for index in 0..<(MerchantKey.limit + 5) {
            memos = MerchantMemory.remembering(
                memos,
                key: "invoice:\(index)",
                merchant: "店\(index)",
                category: .other,
                now: now.addingTimeInterval(Double(index))
            )
        }

        XCTAssertEqual(memos.count, MerchantKey.limit)
        XCTAssertTrue(memos.contains { $0.key == "invoice:\(MerchantKey.limit + 4)" })
        XCTAssertFalse(memos.contains { $0.key == "invoice:0" })
    }

    // MARK: - 保存したものが読み戻せる

    /// 覚えた店が入っていない古いデータも、そのまま読める。
    func testOldHouseholdWithoutMemosStillDecodes() throws {
        let ownerID = UUID()
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "name": "ふたりの家計",
          "monthlyBudget": 120000,
          "members": [
            { "id": "\(ownerID.uuidString)", "displayName": "そら", "role": "owner" }
          ],
          "ownerMemberID": "\(ownerID.uuidString)",
          "createdAt": 700000000,
          "updatedAt": 700000000
        }
        """

        let household = try JSONDecoder().decode(Household.self, from: Data(json.utf8))
        XCTAssertTrue(household.merchantMemos.isEmpty)
    }

    func testMemosSurviveEncodingAndDecoding() throws {
        let memo = MerchantMemo(
            key: "invoice:2170001007389",
            merchant: "Selfix北名古屋",
            category: .transportation,
            updatedAt: now
        )
        let data = try JSONEncoder().encode([memo])
        let decoded = try JSONDecoder().decode([MerchantMemo].self, from: data)
        XCTAssertEqual(decoded, [memo])
    }

    // MARK: - 支出に残る店名

    /// 店名は支出そのものにも残る。あとから「どこで使ったか」を見返せるように。
    func testExpenseKeepsTheShopName() {
        let expense = Expense(
            title: "ガソリン",
            amount: 2_964,
            category: .transportation,
            paidByMemberID: UUID(),
            merchant: "  Selfix北名古屋  "
        )
        XCTAssertEqual(expense.merchant, "Selfix北名古屋")
    }

    /// 手入力の支出には店名が無い。空文字ではなく無しとして扱う。
    func testBlankShopNameBecomesNil() {
        let expense = Expense(
            title: "電車",
            amount: 320,
            category: .transportation,
            paidByMemberID: UUID(),
            merchant: "   "
        )
        XCTAssertNil(expense.merchant)
    }

    /// 店名を持たない古いデータも、そのまま読める。
    func testOldExpenseWithoutShopNameStillDecodes() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "食材",
          "amount": 1280,
          "date": 700000000,
          "category": "groceries",
          "paidByMemberID": "\(UUID().uuidString)",
          "splitMethod": "equally",
          "note": "",
          "createdAt": 700000000,
          "updatedAt": 700000000
        }
        """

        let expense = try JSONDecoder().decode(Expense.self, from: Data(json.utf8))
        XCTAssertNil(expense.merchant)
        XCTAssertEqual(expense.amount, 1_280)
    }

    /// 忘れたら、次に同じ店を読んでも当てはまらない。
    func testForgottenShopIsNoLongerApplied() {
        let memos = [
            MerchantMemo(key: "invoice:1", merchant: "覚えた店", category: .dining, updatedAt: now)
        ]
        let draft = ReceiptDraft(
            merchant: "読み取った名前",
            suggestedCategory: .other,
            shopKey: "invoice:1"
        )
        XCTAssertEqual(MerchantMemory.applying(memos, to: draft).merchant, "覚えた店")

        let afterForgetting = memos.filter { $0.key != "invoice:1" }
        let applied = MerchantMemory.applying(afterForgetting, to: draft)
        XCTAssertEqual(applied.merchant, "読み取った名前")
        XCTAssertFalse(applied.usedMemo)
    }

    // MARK: - 直したことから覚える（レシート読み取りの第3段階）

    private let shop = "tel:0525065600"

    private func observation(
        key: String = "tel:0525065600",
        identifiers: [String] = [],
        merchant: String,
        category: ExpenseCategory,
        corrected: Bool,
        totalLabel: String? = nil,
        totalCorrected: Bool = false
    ) -> MerchantObservation {
        MerchantObservation(
            key: key,
            identifiers: identifiers,
            merchant: merchant,
            category: category,
            corrected: corrected,
            totalLabel: totalLabel,
            totalCorrected: totalCorrected
        )
    }

    /// **一度の読み違いを、そのまま正解として覚えない。** 直さずに1回保存されただけの店は、
    /// 辞書で確かめられた店名と、品や店から決まった種類を上書きしない。
    func testAShopSavedOnceWithoutChangesDoesNotOverrideAWellEvidencedReading() {
        let memos = MerchantMemory.remembering(
            [], observation(merchant: "AEON STYLE", category: .other, corrected: false), now: now
        )
        XCTAssertEqual(memos.first?.isTrusted, false)

        let draft = ReceiptDraft(
            merchant: "イオンスタイルワンダーシティ",
            suggestedCategory: .groceries,
            shopKey: shop,
            merchantIsWellEvidenced: true,
            categoryIsWellEvidenced: true
        )
        let applied = MerchantMemory.applying(memos, to: draft)
        XCTAssertEqual(applied.merchant, "イオンスタイルワンダーシティ")
        XCTAssertEqual(applied.suggestedCategory, .groceries)
    }

    /// 1回保存されただけの店でも、読み取りに手がかりが無いところは埋める（何も出ないよりよい）。
    func testAShopSavedOnceFillsAReadingWithoutEvidence() {
        let memos = MerchantMemory.remembering(
            [], observation(merchant: "Selfix北名古屋", category: .transportation, corrected: false), now: now
        )
        let draft = ReceiptDraft(merchant: "写北名古屋", suggestedCategory: .other, shopKey: shop)

        let applied = MerchantMemory.applying(memos, to: draft)
        XCTAssertEqual(applied.merchant, "Selfix北名古屋")
        XCTAssertEqual(applied.suggestedCategory, .transportation)
    }

    /// 同じ店名と種類で2回保存されたら確かな店にする。空白の違いは同じ内容とみなす。
    func testTwoSavesWithTheSameContentMakeTheShopTrusted() {
        var memos = MerchantMemory.remembering(
            [], observation(merchant: "テンホウ岡谷長地店", category: .dining, corrected: false), now: now
        )
        memos = MerchantMemory.remembering(
            memos,
            observation(merchant: "テンホウ 岡谷長地店", category: .dining, corrected: false),
            now: now.addingTimeInterval(60)
        )
        XCTAssertEqual(memos.count, 1)
        XCTAssertEqual(memos.first?.confirmations, 2)
        XCTAssertEqual(memos.first?.isTrusted, true)

        let draft = ReceiptDraft(
            merchant: "テンホウ",
            suggestedCategory: .dining,
            shopKey: shop,
            merchantIsWellEvidenced: true,
            categoryIsWellEvidenced: true
        )
        XCTAssertEqual(MerchantMemory.applying(memos, to: draft).merchant, "テンホウ岡谷長地店")
    }

    /// 人が直して保存した店は、その1回で確かな店にする（スタンプの店名が読めなかった富士サファリ）。
    func testACorrectedShopIsTrustedAtOnce() {
        let memos = MerchantMemory.remembering(
            [], observation(merchant: "富士サファリパーク", category: .entertainment, corrected: true), now: now
        )
        let draft = ReceiptDraft(
            merchant: "漬汁算素",
            suggestedCategory: .dining,
            shopKey: shop,
            categoryIsWellEvidenced: true
        )

        let applied = MerchantMemory.applying(memos, to: draft)
        XCTAssertEqual(applied.merchant, "富士サファリパーク")
        XCTAssertEqual(applied.suggestedCategory, .entertainment)
    }

    /// 確かな店は、確かめていない読み取りで上書きしない。
    func testAnUnverifiedReadingDoesNotOverwriteATrustedShop() {
        var memos = MerchantMemory.remembering(
            [], observation(merchant: "富士サファリパーク", category: .entertainment, corrected: true), now: now
        )
        memos = MerchantMemory.remembering(
            memos,
            observation(merchant: "漬汁算素", category: .dining, corrected: false),
            now: now.addingTimeInterval(60)
        )
        XCTAssertEqual(memos.map(\.merchant), ["富士サファリパーク"])
        XCTAssertEqual(memos.first?.category, .entertainment)
    }

    /// 間違って覚えた店も、直して保存すれば覚え直す。
    func testACorrectionReplacesATrustedShop() {
        var memos = MerchantMemory.remembering(
            [], observation(merchant: "まちがった名前", category: .other, corrected: true), now: now
        )
        memos = MerchantMemory.remembering(
            memos,
            observation(merchant: "ただしい名前", category: .groceries, corrected: true),
            now: now.addingTimeInterval(60)
        )
        XCTAssertEqual(memos.map(\.merchant), ["ただしい名前"])
        XCTAssertEqual(memos.first?.category, .groceries)
    }

    /// 覚えている店の一覧で名前を直したら、人が直したので確かな店になる。
    func testRenamingMakesTheShopTrusted() {
        let memos = MerchantMemory.remembering(
            [], observation(merchant: "写北名古屋", category: .transportation, corrected: false), now: now
        )
        let renamed = MerchantMemory.renaming(memos, key: shop, to: " Selfix北名古屋 ", now: now)
        XCTAssertEqual(renamed.first?.merchant, "Selfix北名古屋")
        XCTAssertEqual(renamed.first?.isTrusted, true)
    }

    /// 電話番号が読めなかった日でも、前に同じ店で読めた「登録番号＋店名」で同じ店と分かる。
    func testTheShopIsFoundByAnIdentifierReadOnAnEarlierReceipt() {
        let invoiceAndName = "invoice:7010001034871|イオンスタイルワンダーシティ"
        let memos = MerchantMemory.remembering(
            [],
            observation(
                identifiers: [shop, invoiceAndName],
                merchant: "イオン ワンダーシティ",
                category: .groceries,
                corrected: true
            ),
            now: now
        )
        XCTAssertEqual(memos.first?.identifiers, [invoiceAndName])

        let draft = ReceiptDraft(
            merchant: "イオンスタイルワンダーシティ",
            suggestedCategory: .groceries,
            shopKey: invoiceAndName,
            shopIdentifiers: [invoiceAndName],
            merchantIsWellEvidenced: true
        )
        XCTAssertEqual(MerchantMemory.applying(memos, to: draft).merchant, "イオン ワンダーシティ")
    }

    /// 店名と登録番号が同じでも、電話番号が違えば別の支店。覚えた支店の名前を入れない。
    func testADifferentPhoneIsAnotherBranchEvenWithTheSameName() {
        let invoiceAndName = "invoice:7010001034871|マクドナルド"
        let memos = MerchantMemory.remembering(
            [],
            observation(
                identifiers: [shop, invoiceAndName],
                merchant: "マクドナルド 城町店",
                category: .dining,
                corrected: true
            ),
            now: now
        )
        let draft = ReceiptDraft(
            merchant: "マクドナルド",
            suggestedCategory: .dining,
            shopKey: "tel:0529999999",
            shopIdentifiers: ["tel:0529999999", invoiceAndName]
        )
        XCTAssertEqual(MerchantMemory.applying(memos, to: draft).merchant, "マクドナルド")
    }

    /// **品から決まった種類は、覚えた店の種類でも上書きしない。** スーパーで洗剤だけ買った日は日用品。
    func testACategoryDecidedByTheItemsIsKept() {
        let memos = [MerchantMemo(key: shop, merchant: "イオンスタイルワンダーシティ", category: .groceries, updatedAt: now)]
        let draft = ReceiptDraft(
            merchant: "イオンスタイルワンダーシティ",
            suggestedCategory: .household,
            shopKey: shop,
            categoryIsWellEvidenced: true,
            categoryDecidedByItems: true
        )
        XCTAssertEqual(MerchantMemory.applying(memos, to: draft).suggestedCategory, .household)
    }

    /// 品から決まった種類でも、この店で人が直したら、次から直した先にする（家ごとの付け方）。
    /// ほかの種類のときは品から決まった種類のまま。**品の名前は覚えない。**
    func testACorrectedItemsCategoryIsRememberedForThatShop() {
        let memos = MerchantMemory.remembering(
            [],
            MerchantObservation(
                key: shop,
                merchant: "スギ薬局 どこか店",
                category: .health,
                corrected: true,
                readCategory: .groceries,
                readCategoryByItems: true
            ),
            now: now
        )
        XCTAssertEqual(memos.first?.categoryCorrections, ["groceries": .health])

        let food = ReceiptDraft(
            merchant: "スギ薬局 どこか店",
            suggestedCategory: .groceries,
            shopKey: shop,
            categoryIsWellEvidenced: true,
            categoryDecidedByItems: true
        )
        XCTAssertEqual(MerchantMemory.applying(memos, to: food).suggestedCategory, .health)

        var detergent = food
        detergent.suggestedCategory = .household
        XCTAssertEqual(MerchantMemory.applying(memos, to: detergent).suggestedCategory, .household)
    }

    /// 品から決まった種類どおりに保存し直したら、直し先は忘れる（人が元に戻した）。
    func testSavingTheItemsCategoryAgainForgetsTheCorrection() {
        var memos = MerchantMemory.remembering(
            [],
            MerchantObservation(
                key: shop, merchant: "スギ薬局 どこか店", category: .health, corrected: true,
                readCategory: .groceries, readCategoryByItems: true
            ),
            now: now
        )
        memos = MerchantMemory.remembering(
            memos,
            MerchantObservation(
                key: shop, merchant: "スギ薬局 どこか店", category: .groceries, corrected: true,
                readCategory: .groceries, readCategoryByItems: true
            ),
            now: now.addingTimeInterval(60)
        )
        XCTAssertNil(memos.first?.categoryCorrections)
    }

    // MARK: - 人が直した品（2026-10-18 利用者が決定: 店ごとに覚えて共有）

    private func note(_ text: String, name: String? = nil, category: ExpenseCategory?, at date: Date? = nil) -> ItemNote {
        ItemNote(
            key: ReceiptParser.dictionaryKey(text),
            text: text,
            name: name,
            category: category,
            updatedAt: date ?? now
        )
    }

    private var unknownItemReceipt: [RecognizedLine] {
        RecognizedLine.lines(fromPlainText: [
            "あおぞら商店", "TEL 03-0000-0000", "2026/10/18 12:00",
            "ナゾノシナ ¥600", "ボールドJ ¥198", "合計 ¥798"
        ].joined(separator: "\n"))
    }

    /// 人が直した品は、次に同じ店のレシートを読むと、最初から直した名前と種類になる。
    /// 品の種類が変われば、レシート全体の種類も品の重さで決め直す。
    func testACorrectedItemIsUsedOnTheNextReceiptFromThatShop() {
        let memos = MerchantMemory.remembering(
            [],
            MerchantObservation(
                key: "tel:0300000000",
                merchant: "あおぞら商店",
                category: .groceries,
                corrected: true,
                itemNotes: [note("ナゾノシナ", name: "なぞの品", category: .groceries)]
            ),
            now: now
        )
        XCTAssertEqual(memos.first?.itemNotes?.map(\.text), ["ナゾノシナ"])

        let calendar = ReceiptCorpus.calendar
        let before = ReceiptParser.parse(lines: unknownItemReceipt, now: now, calendar: calendar)
        XCTAssertNil(before.items.first?.category, "覚える前は分からない品")

        let draft = ReceiptInterpreter.ruleDraft(lines: unknownItemReceipt, now: now, calendar: calendar, memos: memos)
        XCTAssertEqual(draft.items.map(\.name), ["ナゾノシナ", "ボールドJ"], "読み取った書き方は残す")
        XCTAssertEqual(draft.items.first?.normalizedName, "なぞの品")
        XCTAssertEqual(draft.items.first?.category, .groceries)
        XCTAssertEqual(draft.suggestedCategory, .groceries)
        XCTAssertTrue(draft.categoryDecidedByItems)
    }

    /// 別の店のレシートには、直した品を当てない（店ごとに覚える）。
    func testACorrectedItemIsNotUsedAtAnotherShop() {
        let memos = MerchantMemory.remembering(
            [],
            MerchantObservation(
                key: "tel:0311111111",
                merchant: "べつの店",
                category: .groceries,
                corrected: true,
                itemNotes: [note("ナゾノシナ", category: .groceries)]
            ),
            now: now
        )
        let draft = ReceiptInterpreter.ruleDraft(
            lines: unknownItemReceipt, now: now, calendar: ReceiptCorpus.calendar, memos: memos
        )
        XCTAssertNil(draft.items.first?.category)
    }

    /// 直さずに保存し直しても、覚えた品は消えない。同じ書き方の品を直し直したら新しいほうにする。
    func testItemNotesSurviveLaterSavesAndCanBeRedone() {
        var memos = MerchantMemory.remembering(
            [],
            MerchantObservation(
                key: shop, merchant: "あおぞら商店", category: .groceries, corrected: true,
                itemNotes: [note("ナゾノシナ", category: .groceries)]
            ),
            now: now
        )
        memos = MerchantMemory.remembering(
            memos,
            MerchantObservation(key: shop, merchant: "あおぞら商店", category: .groceries, corrected: false),
            now: now.addingTimeInterval(60)
        )
        XCTAssertEqual(memos.first?.itemNotes?.count, 1)

        memos = MerchantMemory.remembering(
            memos,
            MerchantObservation(
                key: shop, merchant: "あおぞら商店", category: .household, corrected: true,
                itemNotes: [note("ナゾノシナ", category: .household, at: now.addingTimeInterval(120))]
            ),
            now: now.addingTimeInterval(120)
        )
        XCTAssertEqual(memos.first?.itemNotes?.map(\.category), [.household])
    }

    /// 間違って直した品は、覚えている店の一覧から忘れられる。
    func testAnItemNoteCanBeForgotten() {
        let memos = MerchantMemory.remembering(
            [],
            MerchantObservation(
                key: shop, merchant: "あおぞら商店", category: .groceries, corrected: true,
                itemNotes: [note("ナゾノシナ", category: .groceries), note("ボールドJ", category: .household)]
            ),
            now: now
        )
        let once = MerchantMemory.forgettingItemNote(memos, shopKey: shop, noteKey: ReceiptParser.dictionaryKey("ナゾノシナ"))
        XCTAssertEqual(once.first?.itemNotes?.map(\.text), ["ボールドJ"])
        let twice = MerchantMemory.forgettingItemNote(once, shopKey: shop, noteKey: ReceiptParser.dictionaryKey("ボールドJ"))
        XCTAssertNil(twice.first?.itemNotes)
    }

    /// 覚える品の数には上限がある。1つの店で20件、全部の店で600件。新しいものを残す。
    func testItemNotesAreCappedPerShopAndInTotal() {
        let many = (0..<25).map { note("品\($0)ばん", category: .groceries, at: now.addingTimeInterval(Double($0))) }
        let one = MerchantMemory.remembering(
            [],
            MerchantObservation(key: shop, merchant: "あおぞら商店", category: .groceries, corrected: true, itemNotes: many),
            now: now
        )
        XCTAssertEqual(one.first?.itemNotes?.count, MerchantMemory.itemNoteLimit)

        var memos: [MerchantMemo] = []
        for index in 0..<31 {
            let notes = (0..<MerchantMemory.itemNoteLimit).map {
                note("店\(index)の品\($0)", category: .groceries, at: now.addingTimeInterval(Double(index * 100 + $0)))
            }
            memos = MerchantMemory.remembering(
                memos,
                MerchantObservation(
                    key: "tel:03\(10_000_000 + index)",
                    merchant: "店\(index)",
                    category: .groceries,
                    corrected: true,
                    itemNotes: notes
                ),
                now: now.addingTimeInterval(Double(index * 100))
            )
        }
        let total = memos.reduce(0) { $0 + ($1.itemNotes?.count ?? 0) }
        XCTAssertEqual(total, MerchantMemory.totalItemNoteLimit)
        XCTAssertEqual(memos.first { $0.key == "tel:0310000030" }?.itemNotes?.count, MerchantMemory.itemNoteLimit, "新しい店の品は残る")
    }

    /// 2026-10 より前に覚えた店（増えた項目が無い）は、今までどおり確かな店として使う。
    func testMemosFromBeforeTheTrustLevelsAreStillTrusted() throws {
        let json = """
        [{"key": "tel:0525065600", "merchant": "覚えた店", "category": "groceries", "updatedAt": 0}]
        """
        let memos = try JSONDecoder().decode([MerchantMemo].self, from: Data(json.utf8))
        XCTAssertEqual(memos.first?.isTrusted, true)
        XCTAssertNil(memos.first?.identifiers)
        XCTAssertNil(memos.first?.format)
        XCTAssertNil(memos.first?.itemNotes)

        let draft = ReceiptDraft(
            merchant: "読み取った名前",
            suggestedCategory: .other,
            shopKey: shop,
            merchantIsWellEvidenced: true
        )
        XCTAssertEqual(MerchantMemory.applying(memos, to: draft).merchant, "覚えた店")
    }

    /// 増えた項目も、保存して読み戻せる。
    func testTheNewFieldsSurviveEncodingAndDecoding() throws {
        let memos = MerchantMemory.remembering(
            [],
            observation(
                identifiers: [shop, "invoice:7010001034871|あおぞら"],
                merchant: "あおぞら商店",
                category: .groceries,
                corrected: false,
                totalLabel: "オ買物額",
                totalCorrected: true
            ),
            now: now
        )
        let decoded = try JSONDecoder().decode([MerchantMemo].self, from: JSONEncoder().encode(memos))
        XCTAssertEqual(decoded, memos)
        XCTAssertEqual(decoded.first?.format, ReceiptFormat(totalLabel: "オ買物額", corrected: true, seen: 1))
    }

    // MARK: - 店ごとのレシートの書き方

    /// 保存された合計が刷られていた行の書き方。点数や金額の数字は入れない。
    func testTheTotalLabelIsTheRowOfTheSavedTotal() {
        let text = [
            "あおぞら商店", "TEL 03-0000-0000", "りんご ¥198", "食パン ¥248",
            "お買物額 2点 ¥446", "現金 ¥500", "お釣り ¥54"
        ].joined(separator: "\n")
        XCTAssertEqual(ReceiptParser.totalLabel(forTotal: 446, inReceiptText: text), "オ買物額点")
        XCTAssertNil(ReceiptParser.totalLabel(forTotal: 999, inReceiptText: text), "どこにも無い金額からは覚えない")
    }

    private var unusualLabelReceipt: [RecognizedLine] {
        RecognizedLine.lines(fromPlainText: [
            "あおぞら商店", "TEL 03-0000-0000", "2026/10/18 12:00", "お買物額 ¥1,234", "ご優待券 ¥2,000"
        ].joined(separator: "\n"))
    }

    /// 語の一覧に無い書き方（「お買物額」）の店でも、覚えた書き方の行を合計にする。
    func testALearnedTotalLabelFindsTheTotalOnTheNextReceipt() {
        let calendar = ReceiptCorpus.calendar
        let before = ReceiptParser.parse(lines: unusualLabelReceipt, now: now, calendar: calendar)
        XCTAssertTrue(before.amountNeedsConfirmation, "覚える前は、合計の行が分からないので確かめてもらう")

        let format = ReceiptFormat(totalLabel: ReceiptParser.rowLabel("お買物額"), corrected: true, seen: 1)
        let after = ReceiptParser.parse(lines: unusualLabelReceipt, now: now, calendar: calendar, format: format)
        XCTAssertEqual(after.amount, 1_234)
        XCTAssertFalse(after.amountNeedsConfirmation)
    }

    /// 直さずに1回保存されただけの書き方は使わない。2回同じ書き方で保存されたら使う。
    func testAnUnconfirmedTotalLabelIsNotUsedUntilSeenTwice() {
        let label = ReceiptParser.rowLabel("お買物額")
        var memos = MerchantMemory.remembering(
            [],
            observation(key: "tel:0300000000", merchant: "あおぞら商店", category: .groceries,
                        corrected: false, totalLabel: label),
            now: now
        )
        let calendar = ReceiptCorpus.calendar
        XCTAssertNil(MerchantMemory.format(
            for: ReceiptParser.parse(lines: unusualLabelReceipt, now: now, calendar: calendar), in: memos
        ))

        memos = MerchantMemory.remembering(
            memos,
            observation(key: "tel:0300000000", merchant: "あおぞら商店", category: .groceries,
                        corrected: false, totalLabel: label),
            now: now.addingTimeInterval(60)
        )
        let draft = ReceiptInterpreter.ruleDraft(lines: unusualLabelReceipt, now: now, calendar: calendar, memos: memos)
        XCTAssertEqual(draft.amount, 1_234)
    }
}
