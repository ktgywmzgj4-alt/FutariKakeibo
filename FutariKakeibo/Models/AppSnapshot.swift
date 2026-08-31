import Foundation

struct AppSnapshot: Codable, Sendable {
    // v2でカテゴリ別予算と定期支出を追加した。v1のファイルはそのまま読み込める。
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var household: Household?
    var selectedMemberID: UUID?
    var expenses: [Expense]
    var deletedExpenseIDs: [UUID: Date]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        household: Household? = nil,
        selectedMemberID: UUID? = nil,
        expenses: [Expense] = [],
        deletedExpenseIDs: [UUID: Date] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.household = household
        self.selectedMemberID = selectedMemberID
        self.expenses = expenses
        self.deletedExpenseIDs = deletedExpenseIDs
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case household
        case selectedMemberID
        case expenses
        case deletedExpenseIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        household = try container.decodeIfPresent(Household.self, forKey: .household)
        selectedMemberID = try container.decodeIfPresent(UUID.self, forKey: .selectedMemberID)
        expenses = try container.decodeIfPresent([Expense].self, forKey: .expenses) ?? []
        deletedExpenseIDs = try container.decodeIfPresent([UUID: Date].self, forKey: .deletedExpenseIDs) ?? [:]
    }
}
