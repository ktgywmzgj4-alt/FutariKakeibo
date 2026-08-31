import XCTest
@testable import FutariKakeibo

final class CategoryBudgetTests: XCTestCase {
    func testNormalizedRemovesDuplicatesZerosAndKeepsCategoryOrder() {
        let budgets = CategoryBudget.normalized([
            CategoryBudget(category: .dining, amount: 20_000),
            CategoryBudget(category: .groceries, amount: 50_000),
            CategoryBudget(category: .dining, amount: 99_000),
            CategoryBudget(category: .travel, amount: 0)
        ])

        XCTAssertEqual(budgets.map(\.category), [.groceries, .dining])
        XCTAssertEqual(budgets.map(\.amount), [50_000, 20_000])
    }

    func testNegativeAmountBecomesZero() {
        XCTAssertEqual(CategoryBudget(category: .dining, amount: -100).amount, 0)
    }

    func testStatusesSortByHowMuchOfTheBudgetIsUsed() {
        let payerID = UUID()
        let expenses = [
            Expense(title: "食材", amount: 45_000, category: .groceries, paidByMemberID: payerID),
            Expense(title: "外食", amount: 24_000, category: .dining, paidByMemberID: payerID)
        ]

        let statuses = LedgerCalculator.categoryBudgetStatuses(
            expenses: expenses,
            budgets: [
                CategoryBudget(category: .groceries, amount: 50_000),
                CategoryBudget(category: .dining, amount: 20_000)
            ]
        )

        XCTAssertEqual(statuses.map(\.category), [.dining, .groceries])
        XCTAssertTrue(statuses[0].isOverBudget)
        XCTAssertEqual(statuses[0].remaining, -4_000)
        XCTAssertFalse(statuses[1].isOverBudget)
        XCTAssertEqual(statuses[1].remaining, 5_000)
        XCTAssertEqual(statuses[1].progress, 0.9, accuracy: 0.0001)
    }

    func testCategoryWithoutExpensesStaysAtZero() {
        let statuses = LedgerCalculator.categoryBudgetStatuses(
            expenses: [],
            budgets: [CategoryBudget(category: .travel, amount: 30_000)]
        )

        XCTAssertEqual(statuses.count, 1)
        XCTAssertEqual(statuses[0].spent, 0)
        XCTAssertEqual(statuses[0].progress, 0)
        XCTAssertEqual(LedgerCalculator.totalCategoryBudget([CategoryBudget(category: .travel, amount: 30_000)]), 30_000)
    }
}
