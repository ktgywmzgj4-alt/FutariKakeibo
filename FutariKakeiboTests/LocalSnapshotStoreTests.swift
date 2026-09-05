import XCTest
@testable import FutariKakeibo

final class LocalSnapshotStoreTests: XCTestCase {
    @MainActor
    func testUpdatedMemberColorsPersistWithNamesAndBalances() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let localStore = LocalSnapshotStore(directoryURL: directory)
        let cloudService = CloudKitSyncService()
        let images = ReceiptImageLibrary(store: ReceiptImageStore(directoryURL: directory), cloudService: cloudService)
        let store = AppStore(localStore: localStore, cloudService: cloudService, receiptImages: images)
        await store.createHousehold(selfName: "そら", partnerName: "つばさ", monthlyBudget: 80_000)
        let original = try XCTUnwrap(store.household)
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let expense = Expense(title: "食材", amount: 2_230, date: savedAt, category: .groceries,
                              paidByMemberID: original.members[0].id, createdAt: savedAt, updatedAt: savedAt)
        await store.addExpense(expense)
        var members = original.members
        members[0].color = .purple
        members[1].color = .orange
        members[0].displayName = "  新しい呼び名  "
        await store.updateHousehold(name: original.name, monthlyBudget: original.monthlyBudget, members: members)
        XCTAssertNil(store.errorMessage)
        let saved = try await localStore.load()
        XCTAssertEqual(saved.schemaVersion, AppSnapshot.currentSchemaVersion)
        XCTAssertEqual(saved.household?.id, original.id)
        XCTAssertEqual(saved.household?.ownerMemberID, original.ownerMemberID)
        XCTAssertEqual(saved.household?.members.map(\.id), original.members.map(\.id))
        XCTAssertEqual(saved.household?.members.map(\.color), [.purple, .orange])
        XCTAssertEqual(saved.household?.members.first?.displayName, "新しい呼び名")
        XCTAssertEqual(saved.household?.monthlyBudget, 80_000)
        XCTAssertEqual(saved.expenses, [expense])
        XCTAssertEqual(saved.selectedMemberID, original.ownerMemberID)
        XCTAssertEqual(store.syncState, .localOnly)
    }

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
