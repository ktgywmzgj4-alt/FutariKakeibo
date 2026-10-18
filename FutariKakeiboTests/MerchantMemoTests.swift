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
}
