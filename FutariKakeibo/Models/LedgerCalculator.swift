import Foundation

enum LedgerCalculator {
    struct Settlement: Equatable, Sendable {
        var payer: Member?
        var receiver: Member?
        var amount: Int

        static let settled = Settlement(payer: nil, receiver: nil, amount: 0)
    }

    static func expenses(
        _ expenses: [Expense],
        in month: Date,
        calendar: Calendar = .current
    ) -> [Expense] {
        expenses.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    static func total(_ expenses: [Expense]) -> Int {
        expenses.reduce(0) { $0 + $1.amount }
    }

    static func categoryTotals(_ expenses: [Expense]) -> [ExpenseCategory: Int] {
        Dictionary(grouping: expenses, by: \.category)
            .mapValues { total($0) }
    }

    static func settlement(expenses: [Expense], household: Household) -> Settlement {
        guard household.members.count == 2 else { return .settled }

        let sharedExpenses = expenses.filter { $0.splitMethod == .equally }
        let first = household.members[0]
        let second = household.members[1]
        // 奇数円は各支出の支払者が1円多く負担し、相手は整数の半額を返す。
        let firstBalance = sharedExpenses.reduce(0) { balance, expense in
            let reimbursement = expense.amount / 2
            if expense.paidByMemberID == first.id {
                return balance + reimbursement
            }
            if expense.paidByMemberID == second.id {
                return balance - reimbursement
            }
            return balance
        }

        if firstBalance > 0 {
            return Settlement(payer: second, receiver: first, amount: firstBalance)
        }
        if firstBalance < 0 {
            return Settlement(payer: first, receiver: second, amount: abs(firstBalance))
        }
        return .settled
    }

    static func budgetProgress(total: Int, budget: Int) -> Double {
        guard budget > 0 else { return 0 }
        return min(max(Double(total) / Double(budget), 0), 1)
    }
}
