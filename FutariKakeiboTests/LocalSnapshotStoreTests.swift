import XCTest
@testable import FutariKakeibo

final class LocalSnapshotStoreTests: XCTestCase {
    func testRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let owner = Member(displayName: "自分", role: .owner)
        let partner = Member(displayName: "相手", role: .partner)
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let household = Household(
            monthlyBudget: 80_000,
            members: [owner, partner],
            ownerMemberID: owner.id,
            createdAt: savedAt,
            updatedAt: savedAt
        )
        let expense = Expense(
            title: "食材",
            amount: 1_280,
            date: savedAt,
            category: .groceries,
            paidByMemberID: owner.id,
            createdAt: savedAt,
            updatedAt: savedAt
        )
        let expected = AppSnapshot(
            household: household,
            selectedMemberID: owner.id,
            expenses: [expense],
            deletedExpenseIDs: [UUID(): savedAt]
        )
        let store = LocalSnapshotStore(directoryURL: directory)

        try await store.save(expected)
        let actual = try await store.load()

        XCTAssertEqual(actual.household, household)
        XCTAssertEqual(actual.selectedMemberID, owner.id)
        XCTAssertEqual(actual.expenses, [expense])
        XCTAssertEqual(actual.deletedExpenseIDs, expected.deletedExpenseIDs)
    }

    func testCSVUsesUTF8BOMAndEscapesCommas() throws {
        let owner = Member(displayName: "自分", role: .owner)
        let partner = Member(displayName: "相手", role: .partner)
        let household = Household(
            monthlyBudget: 80_000,
            members: [owner, partner],
            ownerMemberID: owner.id
        )
        let expense = Expense(
            title: "スーパー,駅前店",
            amount: 1_280,
            category: .groceries,
            paidByMemberID: owner.id,
            note: "\"特売\""
        )

        let url = try CSVExporter.makeFile(expenses: [expense], household: household)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(data.starts(with: [0xEF, 0xBB, 0xBF]))
        XCTAssertTrue(text.contains("\"スーパー,駅前店\""))
        XCTAssertTrue(text.contains("\"\"\"特売\"\"\""))
    }
}
