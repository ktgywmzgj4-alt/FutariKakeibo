import Foundation

struct AppSnapshot: Codable, Sendable {
    // v2でカテゴリ別予算と定期支出、v3で収入、v4でレシート画像の送信待ちを追加した。
    // v5でメンバーの色IDを追加。古いファイルはそのまま読み込める。
    static let currentSchemaVersion = 5

    var schemaVersion: Int
    var household: Household?
    var selectedMemberID: UUID?
    var expenses: [Expense]
    var incomes: [Income]
    var deletedExpenseIDs: [UUID: Date]
    var deletedIncomeIDs: [UUID: Date]
    /// まだiCloudへ送れていないレシート画像のID。
    ///
    /// 端末内が唯一の原本なので、容量の整理で消してはいけない目印にもなる。
    /// 送れたら消す。共有していないときは、ここに入ったまま残る。
    var pendingReceiptImageIDs: [UUID]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        household: Household? = nil,
        selectedMemberID: UUID? = nil,
        expenses: [Expense] = [],
        incomes: [Income] = [],
        deletedExpenseIDs: [UUID: Date] = [:],
        deletedIncomeIDs: [UUID: Date] = [:],
        pendingReceiptImageIDs: [UUID] = []
    ) {
        self.schemaVersion = schemaVersion
        self.household = household
        self.selectedMemberID = selectedMemberID
        self.expenses = expenses
        self.incomes = incomes
        self.deletedExpenseIDs = deletedExpenseIDs
        self.deletedIncomeIDs = deletedIncomeIDs
        self.pendingReceiptImageIDs = pendingReceiptImageIDs
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case household
        case selectedMemberID
        case expenses
        case incomes
        case deletedExpenseIDs
        case deletedIncomeIDs
        case pendingReceiptImageIDs
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
        pendingReceiptImageIDs = try container.decodeIfPresent([UUID].self, forKey: .pendingReceiptImageIDs) ?? []
    }
}
