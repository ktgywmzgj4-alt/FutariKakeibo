import Foundation

struct AppSnapshot: Codable, Sendable {
    // v2でカテゴリ別予算と定期支出、v3で収入、v4でレシート画像の送信待ちを追加した。
    // 古いファイルはそのまま読み込める。
    //
    // 発行した合言葉の控え（`issuedInvites`、2026-10-19）では版を上げていない。
    // 古い版のアプリは、自分より新しい版のファイルを読まずに止まる（`LocalSnapshotStore`）。
    // TestFlightで前のビルドに戻したときに家計簿が開けなくなるので、無くても困らない項目を
    // 足すだけなら版はそのままにする。古い版は知らない項目を読み飛ばす。
    static let currentSchemaVersion = 4

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
    /// この端末が発行した合言葉の控え（`IssuedInvite`）。使われた・期限の切れたものを
    /// 公開データベースから消すために残す。消したら控えからも外す。
    var issuedInvites: [IssuedInvite]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        household: Household? = nil,
        selectedMemberID: UUID? = nil,
        expenses: [Expense] = [],
        incomes: [Income] = [],
        deletedExpenseIDs: [UUID: Date] = [:],
        deletedIncomeIDs: [UUID: Date] = [:],
        pendingReceiptImageIDs: [UUID] = [],
        issuedInvites: [IssuedInvite] = []
    ) {
        self.schemaVersion = schemaVersion
        self.household = household
        self.selectedMemberID = selectedMemberID
        self.expenses = expenses
        self.incomes = incomes
        self.deletedExpenseIDs = deletedExpenseIDs
        self.deletedIncomeIDs = deletedIncomeIDs
        self.pendingReceiptImageIDs = pendingReceiptImageIDs
        self.issuedInvites = issuedInvites
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
        case issuedInvites
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
        issuedInvites = try container.decodeIfPresent([IssuedInvite].self, forKey: .issuedInvites) ?? []
    }
}
