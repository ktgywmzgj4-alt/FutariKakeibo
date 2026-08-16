@preconcurrency import CloudKit
import Foundation

@MainActor
final class AppStore: ObservableObject {
    enum SyncState: Equatable {
        case localOnly
        case syncing
        case synced(Date)
        case failed(String)

        var label: String {
            switch self {
            case .localOnly: "このiPhone内に保存中"
            case .syncing: "iCloudと同期中…"
            case let .synced(date):
                "同期済み \(date.formatted(date: .omitted, time: .shortened))"
            case .failed: "同期できませんでした"
            }
        }
    }

    struct ShareConfiguration: Identifiable {
        let id = UUID()
        let share: CKShare
        let container: CKContainer
    }

    @Published private(set) var snapshot = AppSnapshot()
    @Published private(set) var isLoading = true
    @Published var selectedMonth = Date.now
    @Published var errorMessage: String?
    @Published private(set) var syncState: SyncState = .localOnly
    @Published var shareConfiguration: ShareConfiguration?

    private let localStore: LocalSnapshotStore
    private let cloudService: CloudKitSyncService
    private var didLoad = false

    init(
        localStore: LocalSnapshotStore = LocalSnapshotStore(),
        cloudService: CloudKitSyncService = CloudKitSyncService()
    ) {
        self.localStore = localStore
        self.cloudService = cloudService
    }

    var household: Household? { snapshot.household }
    var expenses: [Expense] { snapshot.expenses }
    var selectedMemberID: UUID? { snapshot.selectedMemberID }

    var monthlyExpenses: [Expense] {
        LedgerCalculator.expenses(snapshot.expenses, in: selectedMonth)
            .sorted { $0.date > $1.date }
    }

    var monthlyTotal: Int { LedgerCalculator.total(monthlyExpenses) }

    var budgetProgress: Double {
        LedgerCalculator.budgetProgress(
            total: monthlyTotal,
            budget: snapshot.household?.monthlyBudget ?? 0
        )
    }

    var settlement: LedgerCalculator.Settlement {
        guard let household = snapshot.household else { return .settled }
        return LedgerCalculator.settlement(expenses: monthlyExpenses, household: household)
    }

    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        defer { isLoading = false }
        do {
            snapshot = try await localStore.load()
            syncState = snapshot.household?.cloudLocation == nil ? .localOnly : .synced(.now)
        } catch {
            errorMessage = "保存データを読み込めませんでした。データは上書きしていません。\n\(error.localizedDescription)"
        }
    }

    func createHousehold(selfName: String, partnerName: String, monthlyBudget: Int) async {
        let owner = Member(displayName: selfName.isEmpty ? "自分" : selfName, role: .owner)
        let partner = Member(displayName: partnerName.isEmpty ? "パートナー" : partnerName, role: .partner)
        snapshot = AppSnapshot(
            household: Household(
                monthlyBudget: monthlyBudget,
                members: [owner, partner],
                ownerMemberID: owner.id
            ),
            selectedMemberID: owner.id
        )
        await persistLocally()
    }

    func addExpense(_ expense: Expense) async {
        guard expense.isValid else {
            errorMessage = "内容と1円以上の金額を入力してください。"
            return
        }
        snapshot.expenses.append(expense)
        snapshot.expenses.sort { $0.date > $1.date }
        await persistLocally()
        await upload(expense)
    }

    func updateExpense(_ expense: Expense) async {
        guard expense.isValid else {
            errorMessage = "内容と1円以上の金額を入力してください。"
            return
        }
        guard let index = snapshot.expenses.firstIndex(where: { $0.id == expense.id }) else { return }
        var changed = expense
        changed.updatedAt = .now
        snapshot.expenses[index] = changed
        snapshot.expenses.sort { $0.date > $1.date }
        await persistLocally()
        await upload(changed)
    }

    func deleteExpense(_ expense: Expense) async {
        snapshot.expenses.removeAll { $0.id == expense.id }
        let deletedAt = Date.now
        if snapshot.household?.cloudLocation != nil {
            snapshot.deletedExpenseIDs[expense.id] = deletedAt
        }
        await persistLocally()

        guard let household = snapshot.household, household.cloudLocation != nil else { return }
        do {
            try await cloudService.deleteExpense(
                id: expense.id,
                deletedAt: deletedAt,
                household: household
            )
            syncState = .synced(.now)
        } catch {
            syncState = .failed(error.localizedDescription)
        }
    }

    func updateHousehold(name: String, monthlyBudget: Int, members: [Member]) async {
        guard var household = snapshot.household else { return }
        household.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "ふたりの家計"
            : name.trimmingCharacters(in: .whitespacesAndNewlines)
        household.monthlyBudget = max(monthlyBudget, 0)
        household.members = Array(members.prefix(2)).map { member in
            var cleaned = member
            let name = member.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.displayName = name.isEmpty
                ? (member.role == .owner ? "自分" : "パートナー")
                : name
            return cleaned
        }
        household.updatedAt = .now
        snapshot.household = household
        await persistLocally()

        guard household.cloudLocation != nil else { return }
        do {
            syncState = .syncing
            try await cloudService.saveHousehold(household)
            syncState = .synced(.now)
        } catch {
            syncState = .failed(error.localizedDescription)
        }
    }

    func prepareCloudShare() async {
        guard var household = snapshot.household else { return }
        syncState = .syncing
        do {
            let result = try await cloudService.prepareShare(
                household: household,
                expenses: snapshot.expenses
            )
            household.cloudLocation = result.0
            snapshot.household = household
            await persistLocally()
            shareConfiguration = ShareConfiguration(
                share: result.1,
                container: cloudService.container
            )
            syncState = .synced(.now)
        } catch {
            syncState = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func acceptPendingShareIfNeeded() async {
        guard let metadata = CloudShareInbox.shared.take() else { return }
        isLoading = true
        syncState = .syncing
        defer { isLoading = false }

        do {
            let location = try await cloudService.acceptShare(metadata)
            let cloud = try await cloudService.fetchSnapshot(at: location)
            var household = cloud.household
            household.cloudLocation = location
            let selectedMember = household.members.first { $0.role == .partner }?.id
                ?? household.members.last?.id
            snapshot = AppSnapshot(
                household: household,
                selectedMemberID: selectedMember,
                expenses: cloud.expenses,
                deletedExpenseIDs: cloud.deletedExpenseIDs
            )
            await persistLocally()
            syncState = .synced(.now)
        } catch {
            syncState = .failed(error.localizedDescription)
            errorMessage = "共有への参加に失敗しました。\n\(error.localizedDescription)"
        }
    }

    func refreshFromCloudIfConfigured() async {
        guard let household = snapshot.household,
              let location = household.cloudLocation,
              syncState != .syncing
        else { return }

        syncState = .syncing
        do {
            // ローカルの未同期変更と削除を先に再送する。
            try await cloudService.saveHousehold(household)
            for expense in snapshot.expenses {
                try await cloudService.saveExpense(expense, household: household)
            }
            for (id, deletedAt) in snapshot.deletedExpenseIDs {
                try await cloudService.deleteExpense(
                    id: id,
                    deletedAt: deletedAt,
                    household: household
                )
            }

            let cloud = try await cloudService.fetchSnapshot(at: location)
            let deletions = snapshot.deletedExpenseIDs.merging(cloud.deletedExpenseIDs) {
                max($0, $1)
            }
            let deleted = Set(deletions.keys)
            let localByID = Dictionary(uniqueKeysWithValues: snapshot.expenses.map { ($0.id, $0) })
            let remoteByID = Dictionary(uniqueKeysWithValues: cloud.expenses.map { ($0.id, $0) })
            let mergedIDs = Set(localByID.keys).union(remoteByID.keys).subtracting(deleted)
            let merged = mergedIDs.compactMap { id -> Expense? in
                switch (localByID[id], remoteByID[id]) {
                case let (local?, remote?): local.updatedAt >= remote.updatedAt ? local : remote
                case let (local?, nil): local
                case let (nil, remote?): remote
                case (nil, nil): nil
                }
            }.sorted { $0.date > $1.date }

            var mergedHousehold = cloud.household
            mergedHousehold.cloudLocation = location
            snapshot.household = mergedHousehold
            snapshot.expenses = merged
            snapshot.deletedExpenseIDs = deletions
            if snapshot.selectedMemberID.flatMap({ mergedHousehold.member(id: $0) }) == nil {
                snapshot.selectedMemberID = mergedHousehold.members.first?.id
            }
            await persistLocally()
            syncState = .synced(.now)
        } catch {
            syncState = .failed(error.localizedDescription)
        }
    }

    func exportCSV() throws -> URL {
        guard let household = snapshot.household else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try CSVExporter.makeFile(expenses: snapshot.expenses, household: household)
    }

    func eraseLocalData() async {
        do {
            try await localStore.deleteAll()
            snapshot = AppSnapshot()
            syncState = .localOnly
        } catch {
            errorMessage = "このiPhone内のデータを削除できませんでした。\n\(error.localizedDescription)"
        }
    }

    func moveMonth(by value: Int) {
        selectedMonth = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) ?? selectedMonth
    }

    private func persistLocally() async {
        do {
            try await localStore.save(snapshot)
        } catch {
            errorMessage = "このiPhoneに保存できませんでした。\n\(error.localizedDescription)"
        }
    }

    private func upload(_ expense: Expense) async {
        guard let household = snapshot.household, household.cloudLocation != nil else { return }
        do {
            syncState = .syncing
            try await cloudService.saveExpense(expense, household: household)
            syncState = .synced(.now)
        } catch {
            syncState = .failed(error.localizedDescription)
        }
    }
}
