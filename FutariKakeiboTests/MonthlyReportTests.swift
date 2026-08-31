import XCTest
@testable import FutariKakeibo

final class MonthlyReportTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    private func makeHousehold() -> (Household, Member, Member) {
        let owner = Member(displayName: "優", role: .owner)
        let partner = Member(displayName: "蒼", role: .partner)
        let household = Household(
            monthlyBudget: 200_000,
            members: [owner, partner],
            ownerMemberID: owner.id
        )
        return (household, owner, partner)
    }

    func testComparesWithThePreviousMonth() {
        let (household, owner, partner) = makeHousehold()
        let expenses = [
            Expense(title: "先月の食材", amount: 30_000, date: date(2026, 7, 10), category: .groceries, paidByMemberID: owner.id),
            Expense(title: "今月の食材", amount: 20_000, date: date(2026, 8, 10), category: .groceries, paidByMemberID: owner.id),
            Expense(title: "今月の外食", amount: 10_000, date: date(2026, 8, 12), category: .dining, paidByMemberID: partner.id)
        ]

        let report = MonthlyReport.make(
            expenses: expenses,
            household: household,
            month: date(2026, 8, 1),
            referenceDate: date(2026, 8, 15),
            calendar: calendar
        )

        XCTAssertEqual(report.total, 30_000)
        XCTAssertEqual(report.previousTotal, 30_000)
        XCTAssertEqual(report.difference, 0)
        XCTAssertEqual(report.changeRatio, 0)
        XCTAssertEqual(report.expenseCount, 2)
    }

    func testTrendKeepsEmptyMonthsAndEndsAtTheSelectedMonth() {
        let (household, owner, _) = makeHousehold()
        let expenses = [
            Expense(title: "食材", amount: 5_000, date: date(2026, 6, 3), category: .groceries, paidByMemberID: owner.id)
        ]

        let report = MonthlyReport.make(
            expenses: expenses,
            household: household,
            month: date(2026, 8, 1),
            trailingMonths: 6,
            referenceDate: date(2026, 8, 15),
            calendar: calendar
        )

        XCTAssertEqual(report.trend.count, 6)
        XCTAssertEqual(report.trend.first?.month, date(2026, 3, 1))
        XCTAssertEqual(report.trend.last?.month, date(2026, 8, 1))
        XCTAssertEqual(report.trend.map(\.total), [0, 0, 0, 5_000, 0, 0])
    }

    func testSplitsCategoriesAndMembersByShare() {
        let (household, owner, partner) = makeHousehold()
        let expenses = [
            Expense(title: "食材", amount: 60_000, date: date(2026, 8, 2), category: .groceries, paidByMemberID: owner.id),
            Expense(title: "外食", amount: 40_000, date: date(2026, 8, 6), category: .dining, paidByMemberID: partner.id)
        ]

        let report = MonthlyReport.make(
            expenses: expenses,
            household: household,
            month: date(2026, 8, 1),
            referenceDate: date(2026, 8, 20),
            calendar: calendar
        )

        XCTAssertEqual(report.categories.first?.category, .groceries)
        XCTAssertEqual(report.categories.first?.share, 0.6)
        XCTAssertEqual(report.members.count, 2)
        XCTAssertEqual(report.members.first { $0.member.id == partner.id }?.paid, 40_000)
        XCTAssertEqual(report.members.first { $0.member.id == partner.id }?.share, 0.4)
        XCTAssertEqual(report.largestExpense?.amount, 60_000)
    }

    func testDailyAverageUsesElapsedDaysForTheCurrentMonth() {
        let (household, owner, _) = makeHousehold()
        let expenses = [
            Expense(title: "食材", amount: 30_000, date: date(2026, 8, 2), category: .groceries, paidByMemberID: owner.id)
        ]

        let current = MonthlyReport.make(
            expenses: expenses,
            household: household,
            month: date(2026, 8, 1),
            referenceDate: date(2026, 8, 10),
            calendar: calendar
        )
        let past = MonthlyReport.make(
            expenses: expenses,
            household: household,
            month: date(2026, 8, 1),
            referenceDate: date(2026, 9, 10),
            calendar: calendar
        )

        XCTAssertEqual(current.dailyAverage, 3_000)
        XCTAssertEqual(past.dailyAverage, 967)
    }

    func testEmptyMonthHasNoRatio() {
        let (household, _, _) = makeHousehold()
        let report = MonthlyReport.make(
            expenses: [],
            household: household,
            month: date(2026, 8, 1),
            referenceDate: date(2026, 8, 15),
            calendar: calendar
        )

        XCTAssertTrue(report.isEmpty)
        XCTAssertNil(report.changeRatio)
        XCTAssertEqual(report.dailyAverage, 0)
        XCTAssertNil(report.largestExpense)
    }
}
