import XCTest
@testable import FutariKakeibo

final class IncomeTests: XCTestCase {
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
        return (
            Household(monthlyBudget: 200_000, members: [owner, partner], ownerMemberID: owner.id),
            owner,
            partner
        )
    }

    func testBalanceSubtractsExpensesFromIncome() {
        let (_, owner, partner) = makeHousehold()
        let incomes = [
            Income(title: "給与", amount: 300_000, date: date(2026, 8, 25), receivedByMemberID: owner.id),
            Income(title: "副収入", amount: 50_000, date: date(2026, 8, 10), source: .sideJob, receivedByMemberID: partner.id)
        ]
        let expenses = [
            Expense(title: "食材", amount: 60_000, date: date(2026, 8, 3), category: .groceries, paidByMemberID: owner.id)
        ]

        let balance = LedgerCalculator.balance(incomes: incomes, expenses: expenses)

        XCTAssertEqual(balance.income, 350_000)
        XCTAssertEqual(balance.expense, 60_000)
        XCTAssertEqual(balance.balance, 290_000)
        XCTAssertFalse(balance.isNegative)
        XCTAssertEqual(balance.savingsRate ?? 0, 290_000.0 / 350_000.0, accuracy: 0.0001)
    }

    func testSpendingMoreThanIncomeIsNegative() {
        let (_, owner, _) = makeHousehold()
        let balance = LedgerCalculator.balance(
            incomes: [Income(title: "給与", amount: 100_000, receivedByMemberID: owner.id)],
            expenses: [Expense(title: "旅行", amount: 130_000, category: .travel, paidByMemberID: owner.id)]
        )

        XCTAssertEqual(balance.balance, -30_000)
        XCTAssertTrue(balance.isNegative)
    }

    func testNoIncomeHasNoSavingsRate() {
        XCTAssertNil(LedgerCalculator.MonthlyBalance.zero.savingsRate)
        XCTAssertEqual(LedgerCalculator.MonthlyBalance.zero.balance, 0)
    }

    func testMonthlyFilterKeepsOnlyThatMonth() {
        let (_, owner, _) = makeHousehold()
        let incomes = [
            Income(title: "8月の給与", amount: 300_000, date: date(2026, 8, 25), receivedByMemberID: owner.id),
            Income(title: "7月の給与", amount: 290_000, date: date(2026, 7, 25), receivedByMemberID: owner.id)
        ]

        let august = LedgerCalculator.incomes(incomes, in: date(2026, 8, 1), calendar: calendar)

        XCTAssertEqual(august.count, 1)
        XCTAssertEqual(LedgerCalculator.totalIncome(august), 300_000)
    }

    func testSourceTotalsGroupByKind() {
        let (_, owner, partner) = makeHousehold()
        let totals = LedgerCalculator.sourceTotals([
            Income(title: "給与", amount: 300_000, source: .salary, receivedByMemberID: owner.id),
            Income(title: "給与", amount: 250_000, source: .salary, receivedByMemberID: partner.id),
            Income(title: "賞与", amount: 400_000, source: .bonus, receivedByMemberID: owner.id)
        ])

        XCTAssertEqual(totals[.salary], 550_000)
        XCTAssertEqual(totals[.bonus], 400_000)
        XCTAssertNil(totals[.sideJob])
    }

    func testReportCarriesIncomeAndComparesWithLastMonth() {
        let (household, owner, _) = makeHousehold()
        let incomes = [
            Income(title: "8月の給与", amount: 300_000, date: date(2026, 8, 25), receivedByMemberID: owner.id),
            Income(title: "7月の給与", amount: 280_000, date: date(2026, 7, 25), receivedByMemberID: owner.id)
        ]
        let expenses = [
            Expense(title: "食材", amount: 40_000, date: date(2026, 8, 5), category: .groceries, paidByMemberID: owner.id)
        ]

        let report = MonthlyReport.make(
            expenses: expenses,
            incomes: incomes,
            household: household,
            month: date(2026, 8, 1),
            referenceDate: date(2026, 8, 26),
            calendar: calendar
        )

        XCTAssertEqual(report.income, 300_000)
        XCTAssertEqual(report.previousIncome, 280_000)
        XCTAssertEqual(report.incomeCount, 1)
        XCTAssertEqual(report.balance.balance, 260_000)
        XCTAssertEqual(report.previousBalance, 280_000)
        XCTAssertEqual(report.trend.last?.income, 300_000)
        XCTAssertEqual(report.trend.last?.expense, 40_000)
        XCTAssertEqual(report.trend.last?.balance, 260_000)
        XCTAssertFalse(report.isEmpty)
    }

    func testCSVKeepsBothKindsInDateOrder() throws {
        let (household, owner, _) = makeHousehold()
        let expense = Expense(
            title: "食材",
            amount: 6_480,
            date: date(2026, 8, 2),
            category: .groceries,
            paidByMemberID: owner.id
        )
        let income = Income(
            title: "8月の給与",
            amount: 300_000,
            date: date(2026, 8, 25),
            receivedByMemberID: owner.id
        )

        let url = try CSVExporter.makeFile(
            expenses: [expense],
            incomes: [income],
            household: household
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        let lines = text.split(separator: "\n").map(String.init)

        XCTAssertTrue(lines[0].hasSuffix("種別,日付,内容,金額,カテゴリ,相手,分け方,メモ"))
        XCTAssertTrue(lines[1].contains("\"支出\""))
        XCTAssertTrue(lines[1].contains("\"2026-08-02\""))
        XCTAssertTrue(lines[2].contains("\"収入\""))
        XCTAssertTrue(lines[2].contains("\"給与\""))
    }

    func testVersionTwoSnapshotWithoutIncomesStillDecodes() throws {
        let ownerID = UUID()
        let json = """
        {
          "schemaVersion": 2,
          "household": {
            "id": "\(UUID().uuidString)",
            "name": "ふたりの家計",
            "monthlyBudget": 90000,
            "members": [
              { "id": "\(ownerID.uuidString)", "displayName": "自分", "role": "owner" }
            ],
            "ownerMemberID": "\(ownerID.uuidString)",
            "categoryBudgets": [],
            "recurringExpenses": [],
            "createdAt": 700000000,
            "updatedAt": 700000000
          },
          "expenses": [],
          "deletedExpenseIDs": []
        }
        """

        let snapshot = try JSONDecoder().decode(AppSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.schemaVersion, 2)
        XCTAssertTrue(snapshot.incomes.isEmpty)
        XCTAssertTrue(snapshot.deletedIncomeIDs.isEmpty)
    }
}
