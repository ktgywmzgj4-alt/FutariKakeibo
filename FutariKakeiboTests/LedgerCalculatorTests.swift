import XCTest
@testable import FutariKakeibo

final class LedgerCalculatorTests: XCTestCase {
    func testSettlementUsesOnlyEquallySplitExpenses() {
        let first = Member(displayName: "優", role: .owner)
        let second = Member(displayName: "パートナー", role: .partner)
        let household = Household(
            monthlyBudget: 100_000,
            members: [first, second],
            ownerMemberID: first.id
        )
        let expenses = [
            Expense(title: "食材", amount: 8_000, category: .groceries, paidByMemberID: first.id),
            Expense(title: "外食", amount: 2_000, category: .dining, paidByMemberID: second.id),
            Expense(
                title: "個人の服",
                amount: 20_000,
                category: .beauty,
                paidByMemberID: second.id,
                splitMethod: .personal
            )
        ]

        let result = LedgerCalculator.settlement(expenses: expenses, household: household)

        XCTAssertEqual(result.payer?.id, second.id)
        XCTAssertEqual(result.receiver?.id, first.id)
        XCTAssertEqual(result.amount, 3_000)
    }

    func testBudgetProgressIsClamped() {
        XCTAssertEqual(LedgerCalculator.budgetProgress(total: 50_000, budget: 100_000), 0.5)
        XCTAssertEqual(LedgerCalculator.budgetProgress(total: 150_000, budget: 100_000), 1)
        XCTAssertEqual(LedgerCalculator.budgetProgress(total: 10, budget: 0), 0)
    }

    func testOddYenRemainsWithTheMemberWhoPaid() {
        let first = Member(displayName: "優", role: .owner)
        let second = Member(displayName: "パートナー", role: .partner)
        let household = Household(
            monthlyBudget: 100_000,
            members: [first, second],
            ownerMemberID: first.id
        )

        let firstPaid = LedgerCalculator.settlement(
            expenses: [
                Expense(title: "奇数の支出", amount: 1_001, category: .other, paidByMemberID: first.id)
            ],
            household: household
        )
        XCTAssertEqual(firstPaid.payer?.id, second.id)
        XCTAssertEqual(firstPaid.receiver?.id, first.id)
        XCTAssertEqual(firstPaid.amount, 500)

        let secondPaid = LedgerCalculator.settlement(
            expenses: [
                Expense(title: "奇数の支出", amount: 1_001, category: .other, paidByMemberID: second.id)
            ],
            household: household
        )
        XCTAssertEqual(secondPaid.payer?.id, first.id)
        XCTAssertEqual(secondPaid.receiver?.id, second.id)
        XCTAssertEqual(secondPaid.amount, 500)
    }
}
