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
    /// 直近の自動計上で何件追加したか。ホーム画面の通知に使う。
    @Published var lastRecurringInsertCount = 0

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

    var incomes: [Income] { snapshot.incomes }

    var monthlyIncomes: [Income] {
        LedgerCalculator.incomes(snapshot.incomes, in: selectedMonth)
            .sorted { $0.date > $1.date }
    }

    var monthlyIncomeTotal: Int { LedgerCalculator.totalIncome(monthlyIncomes) }

    /// 表示中の月の収支。収入から支出を引いた残り。
    var monthlyBalance: LedgerCalculator.MonthlyBalance {
        LedgerCalculator.balance(incomes: monthlyIncomes, expenses: monthlyExpenses)
    }

    var recurringExpenses: [RecurringExpense] {
        snapshot.household?.recurringExpenses ?? []
    }

    var categoryBudgetStatuses: [LedgerCalculator.CategoryBudgetStatus] {
        guard let household = snapshot.household else { return [] }
        return LedgerCalculator.categoryBudgetStatuses(
            expenses: monthlyExpenses,
            budgets: household.categoryBudgets
        )
    }

    var monthlyReport: MonthlyReport {
        guard let household = snapshot.household else { return .empty }
        return MonthlyReport.make(
            expenses: snapshot.expenses,
            incomes: snapshot.incomes,
            household: household,
            month: selectedMonth
        )
    }

    /// 表示中の月に、これから自動で計上される予定。
    var upcomingRecurringOccurrences: [RecurringExpenseScheduler.Occurrence] {
        RecurringExpenseScheduler.upcomingOccurrences(
            templates: snapshot.household?.recurringExpenses ?? [],
            in: selectedMonth
        )
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
            return
        }
        await applyRecurringExpenses()
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
        // 定期支出から作った回は、削除印を残さないと次の起動で作り直してしまう。
        if snapshot.household?.cloudLocation != nil || expense.isRecurring {
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

    // MARK: - 収入

    func addIncome(_ income: Income) async {
        guard income.isValid else {
            errorMessage = "内容と1円以上の金額を入力してください。"
            return
        }
        snapshot.incomes.append(income)
        snapshot.incomes.sort { $0.date > $1.date }
        await persistLocally()
        await uploadIncome(income)
    }

    func updateIncome(_ income: Income) async {
        guard income.isValid else {
            errorMessage = "内容と1円以上の金額を入力してください。"
            return
        }
        guard let index = snapshot.incomes.firstIndex(where: { $0.id == income.id }) else { return }
        var changed = income
        changed.updatedAt = .now
        snapshot.incomes[index] = changed
        snapshot.incomes.sort { $0.date > $1.date }
        await persistLocally()
        await uploadIncome(changed)
    }

    func deleteIncome(_ income: Income) async {
        snapshot.incomes.removeAll { $0.id == income.id }
        let deletedAt = Date.now
        if snapshot.household?.cloudLocation != nil {
            snapshot.deletedIncomeIDs[income.id] = deletedAt
        }
        await persistLocally()

        guard let household = snapshot.household, household.cloudLocation != nil else { return }
        do {
            try await cloudService.deleteIncome(
                id: income.id,
                deletedAt: deletedAt,
                household: household
            )
            syncState = .synced(.now)
        } catch {
            syncState = .failed(error.localizedDescription)
        }
    }

    private func uploadIncome(_ income: Income) async {
        guard let household = snapshot.household, household.cloudLocation != nil else { return }
        do {
            syncState = .syncing
            try await cloudService.saveIncome(income, household: household)
            syncState = .synced(.now)
        } catch {
            syncState = .failed(error.localizedDescription)
        }
    }

    func updateHousehold(
        name: String,
        monthlyBudget: Int,
        members: [Member],
        categoryBudgets: [CategoryBudget]? = nil
    ) async {
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
        if let categoryBudgets {
            household.categoryBudgets = CategoryBudget.normalized(categoryBudgets)
        }
        await saveHousehold(household)
    }

    func updateCategoryBudgets(_ budgets: [CategoryBudget]) async {
        guard var household = snapshot.household else { return }
        household.categoryBudgets = CategoryBudget.normalized(budgets)
        await saveHousehold(household)
    }

    // MARK: - 定期支出

    func addRecurringExpense(_ template: RecurringExpense) async {
        guard var household = snapshot.household else { return }
        guard template.isValid, template.hasValidPeriod else {
            errorMessage = "内容と1円以上の金額、開始月以降の終了月を入力してください。"
            return
        }
        household.recurringExpenses.append(template)
        await saveHousehold(household)
        await applyRecurringExpenses()
    }

    func updateRecurringExpense(_ template: RecurringExpense) async {
        guard var household = snapshot.household else { return }
        guard template.isValid, template.hasValidPeriod else {
            errorMessage = "内容と1円以上の金額、開始月以降の終了月を入力してください。"
            return
        }
        guard let index = household.recurringExpenses.firstIndex(where: { $0.id == template.id }) else {
            return
        }
        var changed = template
        changed.updatedAt = .now
        household.recurringExpenses[index] = changed
        await saveHousehold(household)
        await applyRecurringExpenses()
    }

    /// ひな形だけを消す。すでに計上済みの支出は実際の記録なので残す。
    func deleteRecurringExpense(_ template: RecurringExpense) async {
        guard var household = snapshot.household else { return }
        household.recurringExpenses.removeAll { $0.id == template.id }
        await saveHousehold(household)
    }

    func setRecurringExpense(_ template: RecurringExpense, isActive: Bool) async {
        var changed = template
        changed.isActive = isActive
        await updateRecurringExpense(changed)
    }

    /// まだ作られていない月の定期支出を作る。何度呼んでも重複しない。
    @discardableResult
    func applyRecurringExpenses(referenceDate: Date = .now) async -> Int {
        guard let household = snapshot.household, !household.recurringExpenses.isEmpty else {
            return 0
        }
        let pending = RecurringExpenseScheduler.pendingExpenses(
            templates: household.recurringExpenses,
            existing: snapshot.expenses,
            deletedExpenseIDs: Set(snapshot.deletedExpenseIDs.keys),
            upTo: referenceDate
        )
        guard !pending.isEmpty else { return 0 }

        snapshot.expenses.append(contentsOf: pending)
        snapshot.expenses.sort { $0.date > $1.date }
        lastRecurringInsertCount = pending.count
        await persistLocally()

        guard household.cloudLocation != nil else { return pending.count }
        do {
            syncState = .syncing
            for expense in pending {
                try await cloudService.saveExpense(expense, household: household)
            }
            syncState = .synced(.now)
        } catch {
            syncState = .failed(error.localizedDescription)
        }
        return pending.count
    }

    // MARK: - iCloud共有

    func prepareCloudShare() async {
        guard var household = snapshot.household else { return }
        syncState = .syncing
        do {
            let result = try await cloudService.prepareShare(
                household: household,
                expenses: snapshot.expenses,
                incomes: snapshot.incomes
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
                incomes: cloud.incomes,
                deletedExpenseIDs: cloud.deletedExpenseIDs,
                deletedIncomeIDs: cloud.deletedIncomeIDs
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
            for income in snapshot.incomes {
                try await cloudService.saveIncome(income, household: household)
            }
            for (id, deletedAt) in snapshot.deletedIncomeIDs {
                try await cloudService.deleteIncome(
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
            let incomeDeletions = snapshot.deletedIncomeIDs.merging(cloud.deletedIncomeIDs) {
                max($0, $1)
            }
            let deletedIncomes = Set(incomeDeletions.keys)
            let localIncomes = Dictionary(uniqueKeysWithValues: snapshot.incomes.map { ($0.id, $0) })
            let remoteIncomes = Dictionary(uniqueKeysWithValues: cloud.incomes.map { ($0.id, $0) })
            let mergedIncomeIDs = Set(localIncomes.keys)
                .union(remoteIncomes.keys)
                .subtracting(deletedIncomes)
            let mergedIncomes = mergedIncomeIDs.compactMap { id -> Income? in
                switch (localIncomes[id], remoteIncomes[id]) {
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
            snapshot.incomes = mergedIncomes
            snapshot.deletedIncomeIDs = incomeDeletions
            if snapshot.selectedMemberID.flatMap({ mergedHousehold.member(id: $0) }) == nil {
                snapshot.selectedMemberID = mergedHousehold.members.first?.id
            }
            await persistLocally()
            syncState = .synced(.now)
        } catch {
            syncState = .failed(error.localizedDescription)
        }

        // 相手が追加したひな形の分も、この端末で計上しておく。
        await applyRecurringExpenses()
    }

    func exportCSV() throws -> URL {
        guard let household = snapshot.household else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try CSVExporter.makeFile(
            expenses: snapshot.expenses,
            incomes: snapshot.incomes,
            household: household
        )
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

    // MARK: - Private

    private func saveHousehold(_ household: Household) async {
        var changed = household
        changed.updatedAt = .now
        snapshot.household = changed
        await persistLocally()

        guard changed.cloudLocation != nil else { return }
        do {
            syncState = .syncing
            try await cloudService.saveHousehold(changed)
            syncState = .synced(.now)
        } catch {
            syncState = .failed(error.localizedDescription)
        }
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
