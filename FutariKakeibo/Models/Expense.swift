import Foundation

struct Expense: Identifiable, Codable, Hashable, Sendable {
    enum SplitMethod: String, Codable, CaseIterable, Identifiable, Sendable {
        case equally
        case personal

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .equally: "2人で折半"
            case .personal: "個人の支出"
            }
        }
    }

    let id: UUID
    var title: String
    var amount: Int
    var date: Date
    var category: ExpenseCategory
    var paidByMemberID: UUID
    var splitMethod: SplitMethod
    var note: String
    /// どこで買ったか。レシートから読み取るか、覚えた店から選ぶ。手入力の支出ではnil。
    var merchant: String?
    /// 定期支出のひな形から自動で作られた場合、そのひな形のID。手入力ならnil。
    var recurringID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        amount: Int,
        date: Date = .now,
        category: ExpenseCategory,
        paidByMemberID: UUID,
        splitMethod: SplitMethod = .equally,
        note: String = "",
        merchant: String? = nil,
        recurringID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.amount = max(amount, 0)
        self.date = date
        self.category = category
        self.paidByMemberID = paidByMemberID
        self.splitMethod = splitMethod
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let shop = merchant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.merchant = shop.isEmpty ? nil : shop
        self.recurringID = recurringID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isValid: Bool {
        !title.isEmpty && amount > 0
    }

    var isRecurring: Bool {
        recurringID != nil
    }
}
