import XCTest
import SwiftUI
@testable import FutariKakeibo

/// v1（カテゴリ別予算・定期支出を持たない）で保存したデータが、そのまま読めることを確かめる。
final class SnapshotCompatibilityTests: XCTestCase {
    func testLegacyMemberColorsDefaultByRole() throws {
        let ownerID = UUID()
        let partnerID = UUID()
        let json = """
        [
          {"id":"\(ownerID)","displayName":"そら","role":"owner"},
          {"id":"\(partnerID)","displayName":"つばさ","role":"partner","colorID":null}
        ]
        """
        let members = try JSONDecoder().decode([Member].self, from: Data(json.utf8))
        XCTAssertEqual(members.map(\.id), [ownerID, partnerID])
        XCTAssertEqual(members.map(\.color), [.blue, .coral])
    }

    func testUnknownMemberColorSurvivesRenaming() throws {
        let json = """
        {"id":"\(UUID())","displayName":"つばさ","role":"partner","colorID":"future-color"}
        """
        var member = try JSONDecoder().decode(Member.self, from: Data(json.utf8))
        XCTAssertEqual(member.color, .coral)
        member.displayName = "新しい呼び名"
        let encoded = try JSONEncoder().encode(member)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(fields["colorID"] as? String, "future-color")
        XCTAssertEqual(fields["displayName"] as? String, "新しい呼び名")
    }

    func testMemberColorsSurviveMembersDataRoundTrip() throws {
        // CloudKitの既存membersDataと同じ[Member]のJSON形式を確認する。
        for color in MemberColor.allCases {
            let owner = Member(displayName: "そら", role: .owner, color: color)
            let partner = Member(displayName: "つばさ", role: .partner, color: .teal)
            let membersData = try JSONEncoder().encode([owner, partner])
            let decoded = try JSONDecoder().decode([Member].self, from: membersData)
            XCTAssertEqual(decoded, [owner, partner])
            XCTAssertEqual(decoded.map(\.color), [color, .teal])
        }
    }

    func testMemberColorsFollowIdentityWhenOrderChanges() {
        let owner = Member(displayName: "そら", role: .owner, color: .pink)
        let partner = Member(displayName: "つばさ", role: .partner, color: .teal)
        let household = Household(monthlyBudget: 80_000, members: [partner, owner], ownerMemberID: owner.id)
        XCTAssertEqual(household.color(of: owner.id), MemberColor.pink.uiColor)
        XCTAssertEqual(household.color(of: partner.id), MemberColor.teal.uiColor)
        XCTAssertEqual(household.color(of: nil), AppTheme.accent)
        XCTAssertEqual(household.color(of: UUID()), AppTheme.accent)
    }

    func testLegacyMemberDecoderCanReadNewMembersData() throws {
        // 旧アプリも共有データの色以外は読める。ただし旧アプリから保存すると色は落ちる。
        struct LegacyMember: Decodable {
            let id: UUID
            let displayName: String
            let role: Member.Role
        }
        let member = Member(displayName: "そら", role: .owner, color: .purple)
        let data = try JSONEncoder().encode([member])
        let decoded = try JSONDecoder().decode([LegacyMember].self, from: data)
        XCTAssertEqual(decoded.first?.id, member.id)
        XCTAssertEqual(decoded.first?.displayName, member.displayName)
        XCTAssertEqual(decoded.first?.role, member.role)
    }

    func testVersionFourSnapshotKeepsLedgerOnUpgrade() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let appDirectory = directory.appendingPathComponent("FutariKakeibo", isDirectory: true)
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        let owner = Member(displayName: "そら", role: .owner)
        let partner = Member(displayName: "つばさ", role: .partner)
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let household = Household(monthlyBudget: 90_000, members: [owner, partner], ownerMemberID: owner.id,
                                  createdAt: savedAt, updatedAt: savedAt)
        let expense = Expense(title: "食材", amount: 3_374, date: savedAt, category: .groceries,
                              paidByMemberID: owner.id, createdAt: savedAt, updatedAt: savedAt)
        let oldSnapshot = AppSnapshot(schemaVersion: 4, household: household, selectedMemberID: partner.id,
                                      expenses: [expense], pendingReceiptImageIDs: [UUID()])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let oldData = try encoder.encode(oldSnapshot)
        XCTAssertFalse(String(decoding: oldData, as: UTF8.self).contains("colorID"))
        try oldData.write(to: appDirectory.appendingPathComponent("snapshot.json"))
        let store = LocalSnapshotStore(directoryURL: directory)
        let loaded = try await store.load()
        XCTAssertEqual(loaded.schemaVersion, 4)
        XCTAssertEqual(loaded.household?.members.map(\.color), [.blue, .coral])
        try await store.save(loaded)
        let upgraded = try await store.load()
        XCTAssertEqual(upgraded.schemaVersion, AppSnapshot.currentSchemaVersion)
        XCTAssertEqual(upgraded.household, household)
        XCTAssertEqual(upgraded.expenses.map(\.id), [expense.id])
        XCTAssertEqual(upgraded.expenses.first?.amount, 3_374)
        XCTAssertEqual(upgraded.selectedMemberID, partner.id)
        XCTAssertEqual(upgraded.pendingReceiptImageIDs, oldSnapshot.pendingReceiptImageIDs)
    }

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
