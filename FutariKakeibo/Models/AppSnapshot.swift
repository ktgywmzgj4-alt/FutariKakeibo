import Foundation

struct AppSnapshot: Codable, Sendable {
    // v2でカテゴリ別予算と定期支出、v3で収入を追加した。古いファイルはそのまま読み込める。
    static let currentSchemaVersion = 3

    var schemaVersion: Int
    var household: Household?
    var selectedMemberID: UUID?
    var expenses: [Expense]
    var incomes: [Income]
    var deletedExpenseIDs: [UUID: Date]
    var deletedIncomeIDs: [UUID: Date]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        household: Household? = nil,
        selectedMemberID: UUID? = nil,
        expenses: [Expense] = [],
        incomes: [Income] = [],
        deletedExpenseIDs: [UUID: Date] = [:],
        deletedIncomeIDs: [UUID: Date] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.household = household
        self.selectedMemberID = selectedMemberID
        self.expenses = expenses
        self.incomes = incomes
        self.deletedExpenseIDs = deletedExpenseIDs
        self.deletedIncomeIDs = deletedIncomeIDs
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case household
        case selectedMemberID
        case expenses
        case incomes
        case deletedExpenseIDs
        case deletedIncomeIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        household = try container.decodeIfPresent(Household.self, forKey: .household)
        selectedMemberID = try container.decodeIfPresent(UUID.self, forKey: .selectedMemberID)
        expenses = try container.decodeIfPresent([Expense].self, forKey: .expenses) ?? []
        incomes = try container.decodeIfPresent([Income].self, forKey: .incomes) ?? []
        deletedExpenseIDs = try container.decodeIfPresent([UUID: Date].self, forKey: .deletedExpenseIDs) ?? [:]
        deletedIncomeIDs = try container.decodeIfPresent([UUID: Date].self, forKey: .deletedIncomeIDs) ?? [:]
    }
}
