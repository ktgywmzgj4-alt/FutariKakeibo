import Foundation

/// 家賃やサブスクのように、毎月ほぼ同じ内容で発生する支出のひな形。
/// ひな形そのものは金額の集計に含めず、月ごとに実際の`Expense`へ展開して使う。
struct RecurringExpense: Identifiable, Codable, Hashable, Sendable {
    static let minimumDayOfMonth = 1
    static let maximumDayOfMonth = 31

    let id: UUID
    var title: String
    var amount: Int
    var category: ExpenseCategory
    var paidByMemberID: UUID
    var splitMethod: Expense.SplitMethod
    var note: String
    /// 1〜31。31日を指定しても、日数の少ない月ではその月の最終日へ寄せる。
    var dayOfMonth: Int
    /// 計上を始める月。日付部分は月初へ丸めて保持する。
    var startMonth: Date
    /// 計上を終える月。nilなら終了を決めていない。
    var endMonth: Date?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        amount: Int,
        category: ExpenseCategory,
        paidByMemberID: UUID,
        splitMethod: Expense.SplitMethod = .equally,
        note: String = "",
        dayOfMonth: Int,
        startMonth: Date = .now,
        endMonth: Date? = nil,
        isActive: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.amount = max(amount, 0)
        self.category = category
        self.paidByMemberID = paidByMemberID
        self.splitMethod = splitMethod
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        self.dayOfMonth = min(max(dayOfMonth, Self.minimumDayOfMonth), Self.maximumDayOfMonth)
        self.startMonth = calendar.startOfMonth(for: startMonth) ?? startMonth
        self.endMonth = endMonth.flatMap { calendar.startOfMonth(for: $0) ?? $0 }
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isValid: Bool {
        !title.isEmpty && amount > 0
    }

    /// 終了月が開始月より前になっていないか。UIの保存可否判定に使う。
    var hasValidPeriod: Bool {
        guard let endMonth else { return true }
        return endMonth >= startMonth
    }

    /// 「毎月25日」のような、一覧に出す短い説明。
    var scheduleDescription: String {
        "毎月\(dayOfMonth)日"
    }
}

extension Calendar {
    /// その日付が属する月の1日0時。月単位の繰り返し計算の基準に使う。
    func startOfMonth(for date: Date) -> Date? {
        self.date(from: dateComponents([.year, .month], from: date))
    }
}
