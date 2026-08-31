import XCTest
@testable import FutariKakeibo

/// v1（カテゴリ別予算・定期支出を持たない）で保存したデータが、そのまま読めることを確かめる。
final class SnapshotCompatibilityTests: XCTestCase {
    func testOldHouseholdJSONStillDecodes() throws {
        let ownerID = UUID()
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "name": "ふたりの家計",
          "monthlyBudget": 120000,
          "members": [
            { "id": "\(ownerID.uuidString)", "displayName": "自分", "role": "owner" }
          ],
          "ownerMemberID": "\(ownerID.uuidString)",
          "createdAt": 700000000,
          "updatedAt": 700000000
        }
        """

        let household = try JSONDecoder().decode(Household.self, from: Data(json.utf8))

        XCTAssertEqual(household.monthlyBudget, 120_000)
        XCTAssertTrue(household.categoryBudgets.isEmpty)
        XCTAssertTrue(household.recurringExpenses.isEmpty)
    }

    func testOldExpenseJSONStillDecodes() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "食材",
          "amount": 1280,
          "date": 700000000,
          "category": "groceries",
          "paidByMemberID": "\(UUID().uuidString)",
          "splitMethod": "equally",
          "note": "",
          "createdAt": 700000000,
          "updatedAt": 700000000
        }
        """

        let expense = try JSONDecoder().decode(Expense.self, from: Data(json.utf8))

        XCTAssertEqual(expense.amount, 1_280)
        XCTAssertNil(expense.recurringID)
        XCTAssertFalse(expense.isRecurring)
    }

    func testVersionOneSnapshotFileLoads() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("FutariKakeibo", isDirectory: true),
            withIntermediateDirectories: true
        )

        let ownerID = UUID()
        let json = """
        {
          "schemaVersion": 1,
          "household": {
            "id": "\(UUID().uuidString)",
            "name": "ふたりの家計",
            "monthlyBudget": 90000,
            "members": [
              { "id": "\(ownerID.uuidString)", "displayName": "自分", "role": "owner" }
            ],
            "ownerMemberID": "\(ownerID.uuidString)",
            "createdAt": 1700000000000,
            "updatedAt": 1700000000000
          },
          "selectedMemberID": "\(ownerID.uuidString)",
          "expenses": [],
          "deletedExpenseIDs": []
        }
        """
        try Data(json.utf8).write(
            to: directory
                .appendingPathComponent("FutariKakeibo", isDirectory: true)
                .appendingPathComponent("snapshot.json")
        )

        let store = LocalSnapshotStore(directoryURL: directory)
        let snapshot = try await store.load()

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.household?.monthlyBudget, 90_000)
        XCTAssertTrue(snapshot.household?.recurringExpenses.isEmpty ?? false)

        // 保存し直すと最新の形式になり、内容は保たれる。
        try await store.save(snapshot)
        let reloaded = try await store.load()
        XCTAssertEqual(reloaded.schemaVersion, AppSnapshot.currentSchemaVersion)
        XCTAssertEqual(reloaded.household?.monthlyBudget, 90_000)
    }
}
