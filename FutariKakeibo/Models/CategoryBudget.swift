import Foundation

/// 「食費は5万円まで」のような、カテゴリごとの月予算。
/// 辞書ではなく配列で持ち、表示順と保存形式を安定させる。
struct CategoryBudget: Identifiable, Codable, Hashable, Sendable {
    var category: ExpenseCategory
    var amount: Int

    var id: ExpenseCategory { category }

    init(category: ExpenseCategory, amount: Int) {
        self.category = category
        self.amount = max(amount, 0)
    }

    /// 同じカテゴリの重複と0円を取り除き、カテゴリの定義順に整える。
    static func normalized(_ budgets: [CategoryBudget]) -> [CategoryBudget] {
        var byCategory: [ExpenseCategory: Int] = [:]
        for budget in budgets where budget.amount > 0 {
            if byCategory[budget.category] == nil {
                byCategory[budget.category] = budget.amount
            }
        }
        return ExpenseCategory.allCases.compactMap { category in
            byCategory[category].map { CategoryBudget(category: category, amount: $0) }
        }
    }
}
