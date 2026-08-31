import Foundation

/// 1か月分の振り返り。グラフと前月比の表示に必要な値だけをまとめて持つ。
struct MonthlyReport: Equatable, Sendable {
    struct MonthTotal: Identifiable, Equatable, Sendable {
        var month: Date
        var total: Int

        var id: Date { month }
    }

    struct CategorySlice: Identifiable, Equatable, Sendable {
        var category: ExpenseCategory
        var total: Int
        var share: Double

        var id: ExpenseCategory { category }
    }

    struct MemberTotal: Identifiable, Equatable, Sendable {
        var member: Member
        var paid: Int
        var share: Double

        var id: UUID { member.id }
    }

    var month: Date
    var total: Int
    var previousTotal: Int
    var expenseCount: Int
    /// 直近数か月の推移。古い月から新しい月の順。
    var trend: [MonthTotal]
    var categories: [CategorySlice]
    var members: [MemberTotal]
    var largestExpense: Expense?
    /// その月の経過日数で割った1日あたりの平均。当月なら今日までで計算する。
    var dailyAverage: Int

    var difference: Int { total - previousTotal }

    /// 前月が0円のときは比率を出さない。
    var changeRatio: Double? {
        guard previousTotal > 0 else { return nil }
        return Double(difference) / Double(previousTotal)
    }

    var isEmpty: Bool { expenseCount == 0 }

    static let empty = MonthlyReport(
        month: .now,
        total: 0,
        previousTotal: 0,
        expenseCount: 0,
        trend: [],
        categories: [],
        members: [],
        largestExpense: nil,
        dailyAverage: 0
    )

    static func make(
        expenses: [Expense],
        household: Household,
        month: Date,
        trailingMonths: Int = 6,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> MonthlyReport {
        let monthlyExpenses = LedgerCalculator.expenses(expenses, in: month, calendar: calendar)
        let total = LedgerCalculator.total(monthlyExpenses)

        let previousMonth = calendar.date(byAdding: .month, value: -1, to: month)
        let previousTotal = previousMonth.map {
            LedgerCalculator.total(LedgerCalculator.expenses(expenses, in: $0, calendar: calendar))
        } ?? 0

        let categoryTotals = LedgerCalculator.categoryTotals(monthlyExpenses)
        let categories = categoryTotals
            .map { category, amount in
                CategorySlice(
                    category: category,
                    total: amount,
                    share: total > 0 ? Double(amount) / Double(total) : 0
                )
            }
            .sorted { $0.total > $1.total }

        let paidByMember = Dictionary(grouping: monthlyExpenses, by: \.paidByMemberID)
            .mapValues { LedgerCalculator.total($0) }
        let members = household.members.map { member in
            let paid = paidByMember[member.id] ?? 0
            return MemberTotal(
                member: member,
                paid: paid,
                share: total > 0 ? Double(paid) / Double(total) : 0
            )
        }

        return MonthlyReport(
            month: month,
            total: total,
            previousTotal: previousTotal,
            expenseCount: monthlyExpenses.count,
            trend: trend(
                expenses: expenses,
                endingAt: month,
                count: max(trailingMonths, 1),
                calendar: calendar
            ),
            categories: categories,
            members: members,
            largestExpense: monthlyExpenses.max { $0.amount < $1.amount },
            dailyAverage: dailyAverage(
                total: total,
                month: month,
                referenceDate: referenceDate,
                calendar: calendar
            )
        )
    }

    /// 指定月を最後尾にした、月別合計の並び。支出のない月も0円として残す。
    static func trend(
        expenses: [Expense],
        endingAt month: Date,
        count: Int,
        calendar: Calendar = .current
    ) -> [MonthTotal] {
        guard let lastMonth = calendar.startOfMonth(for: month) else { return [] }
        return (0..<count)
            .reversed()
            .compactMap { offset -> MonthTotal? in
                guard let target = calendar.date(byAdding: .month, value: -offset, to: lastMonth) else {
                    return nil
                }
                let total = LedgerCalculator.total(
                    LedgerCalculator.expenses(expenses, in: target, calendar: calendar)
                )
                return MonthTotal(month: target, total: total)
            }
    }

    private static func dailyAverage(
        total: Int,
        month: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> Int {
        guard
            total > 0,
            let startOfMonth = calendar.startOfMonth(for: month),
            let range = calendar.range(of: .day, in: .month, for: startOfMonth)
        else { return 0 }

        let elapsedDays: Int
        if calendar.isDate(referenceDate, equalTo: startOfMonth, toGranularity: .month) {
            elapsedDays = calendar.component(.day, from: referenceDate)
        } else {
            elapsedDays = range.count
        }
        return total / max(elapsedDays, 1)
    }
}
