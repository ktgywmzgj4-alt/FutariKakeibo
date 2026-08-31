import Foundation

struct Household: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var monthlyBudget: Int
    var members: [Member]
    var ownerMemberID: UUID
    /// カテゴリごとの月予算。設定していないカテゴリは含まれない。
    var categoryBudgets: [CategoryBudget]
    /// 家賃やサブスクのひな形。実際の支出はここから月ごとに展開する。
    var recurringExpenses: [RecurringExpense]
    var cloudLocation: CloudLocation?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "ふたりの家計",
        monthlyBudget: Int,
        members: [Member],
        ownerMemberID: UUID,
        categoryBudgets: [CategoryBudget] = [],
        recurringExpenses: [RecurringExpense] = [],
        cloudLocation: CloudLocation? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.monthlyBudget = max(monthlyBudget, 0)
        self.members = Array(members.prefix(2))
        self.ownerMemberID = ownerMemberID
        self.categoryBudgets = CategoryBudget.normalized(categoryBudgets)
        self.recurringExpenses = recurringExpenses
        self.cloudLocation = cloudLocation
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var partner: Member? {
        members.first { $0.id != ownerMemberID }
    }

    func member(id: UUID) -> Member? {
        members.first { $0.id == id }
    }

    func categoryBudget(for category: ExpenseCategory) -> Int? {
        categoryBudgets.first { $0.category == category }?.amount
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case monthlyBudget
        case members
        case ownerMemberID
        case categoryBudgets
        case recurringExpenses
        case cloudLocation
        case createdAt
        case updatedAt
    }

    // 旧バージョンで保存したJSONにはカテゴリ予算と定期支出の項目がないため、
    // 欠けていても読み込みを失敗させずに空として扱う。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        monthlyBudget = try container.decode(Int.self, forKey: .monthlyBudget)
        members = try container.decode([Member].self, forKey: .members)
        ownerMemberID = try container.decode(UUID.self, forKey: .ownerMemberID)
        categoryBudgets = try container.decodeIfPresent([CategoryBudget].self, forKey: .categoryBudgets) ?? []
        recurringExpenses = try container.decodeIfPresent([RecurringExpense].self, forKey: .recurringExpenses) ?? []
        cloudLocation = try container.decodeIfPresent(CloudLocation.self, forKey: .cloudLocation)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct CloudLocation: Codable, Hashable, Sendable {
    enum Scope: String, Codable, Sendable {
        case privateDatabase
        case sharedDatabase
    }

    var scope: Scope
    var zoneName: String
    var ownerName: String
    var rootRecordName: String
}
