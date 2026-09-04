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
    /// 相手に伝える合言葉。発行した直後だけ画面に出す。
    @Published var shareInvite: ShareInvite?
    @Published private(set) var isPreparingInvite = false
    /// 直近の自動計上で何件追加したか。ホーム画面の通知に使う。
    @Published var lastRecurringInsertCount = 0

    private let localStore: LocalSnapshotStore
    private let cloudService: CloudKitSyncService
    /// レシート画像の出し入れ。画像は家計簿データとは別に持つ。
    let receiptImages: ReceiptImageLibrary
    private var didLoad = false

    init(
        localStore: LocalSnapshotStore = LocalSnapshotStore(),
        cloudService: CloudKitSyncService = CloudKitSyncService(),
        receiptImages: ReceiptImageLibrary? = nil
    ) {
        self.localStore = localStore
        self.cloudService = cloudService
        self.receiptImages = receiptImages ?? ReceiptImageLibrary(cloudService: cloudService)
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
        tidyReceiptImages()
    }

    func createHousehold(selfName: String, partnerName: String, monthlyBudget: Int) async {
        let owner = Member(displayName: selfName.isEmpty ? "そら" : selfName, role: .owner)
        let partner = Member(displayName: partnerName.isEmpty ? "つばさ" : partnerName, role: .partner)
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
        if let imageID = expense.receiptImageID {
            snapshot.pendingReceiptImageIDs.removeAll { $0 == imageID }
        }
        await persistLocally()

        // 支出と一緒に、その支出のレシート画像も消す。孤立した画像を残さない。
        // 画像のIDは撮るたびに新しく作るので、この1枚が他の支出から使われることはない。
        if let imageID = expense.receiptImageID {
            await receiptImages.remove(
                id: imageID,
                expenseID: expense.id,
                household: snapshot.household
            )
        }

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

    // MARK: - レシート画像

    /// 圧縮済みのレシート画像を支出に結びつける。
    ///
    /// 家計簿データに画像そのものは入れない。画像はファイルとして置き、
    /// 支出にはIDだけを持たせる。共有していれば続けてiCloudへ送る。
    /// 送れなくても記録は残り、`pendingReceiptImageIDs` に残して次の同期でやり直す。
    func attachReceiptImage(_ image: ReceiptImageData, to expenseID: UUID) async {
        guard snapshot.expenses.contains(where: { $0.id == expenseID }) else { return }

        let imageID = UUID()
        do {
            try await receiptImages.attach(image, id: imageID)
        } catch {
            errorMessage = "レシート画像を保存できませんでした。支出のほうは保存されています。\n\(error.localizedDescription)"
            return
        }

        // 端末へ書いているあいだに一覧が並び替わることがあるので、位置は取り直す。
        guard let index = snapshot.expenses.firstIndex(where: { $0.id == expenseID }) else {
            // その支出がもう無いなら、画像だけを残さない。
            await receiptImages.remove(
                id: imageID,
                expenseID: expenseID,
                household: snapshot.household
            )
            return
        }
        let previousImageID = snapshot.expenses[index].receiptImageID
        snapshot.expenses[index].receiptImageID = imageID
        snapshot.expenses[index].updatedAt = .now
        snapshot.pendingReceiptImageIDs.append(imageID)
        if let previousImageID {
            snapshot.pendingReceiptImageIDs.removeAll { $0 == previousImageID }
        }
        let expense = snapshot.expenses[index]
        await persistLocally()

        // 撮り直した場合は、前の画像を残さない。
        if let previousImageID {
            await receiptImages.remove(
                id: previousImageID,
                expenseID: expenseID,
                household: snapshot.household
            )
        }
        await upload(expense)
        await uploadReceiptImage(imageID, expenseID: expenseID)
    }

    /// 支出からレシート画像を外して消す。
    func removeReceiptImage(from expenseID: UUID) async {
        guard
            let index = snapshot.expenses.firstIndex(where: { $0.id == expenseID }),
            let imageID = snapshot.expenses[index].receiptImageID
        else { return }

        snapshot.expenses[index].receiptImageID = nil
        snapshot.expenses[index].updatedAt = .now
        snapshot.pendingReceiptImageIDs.removeAll { $0 == imageID }
        let expense = snapshot.expenses[index]
        await persistLocally()

        await receiptImages.remove(
            id: imageID,
            expenseID: expenseID,
            household: snapshot.household
        )
        await upload(expense)
    }

    /// 一覧で使う小さな画像。**端末内にあるものだけ**を返す。通信はしない。
    func receiptThumbnail(for imageID: UUID) async -> Data? {
        await receiptImages.thumbnail(for: imageID)
    }

    /// 詳細画面で見る画像。端末に無ければiCloudから取ってくる。
    func receiptImage(for expense: Expense) async throws -> Data {
        guard let imageID = expense.receiptImageID else {
            throw ReceiptImageLibrary.LoadError.notStored
        }
        return try await receiptImages.display(
            for: imageID,
            expenseID: expense.id,
            household: snapshot.household
        )
    }

    /// 端末に置いてあるレシート画像の合計の大きさ。設定画面に出すときに使う。
    func receiptImageBytes() async -> Int {
        await receiptImages.totalBytes()
    }

    private func uploadReceiptImage(_ imageID: UUID, expenseID: UUID) async {
        guard let household = snapshot.household, household.cloudLocation != nil else { return }
        do {
            syncState = .syncing
            try await receiptImages.upload(id: imageID, expenseID: expenseID, household: household)
            snapshot.pendingReceiptImageIDs.removeAll { $0 == imageID }
            await persistLocally()
            syncState = .synced(.now)
        } catch {
            // 画像を送れなくても支出は残る。次の同期でもう一度試す。
            syncState = .failed(error.localizedDescription)
        }
    }

    /// どの支出からも使われていない画像と、増えすぎた分を片付ける。
    ///
    /// 起動を待たせたくないので待ち合わせない。まだ送れていない画像は
    /// この端末にしか無いので、容量の整理では消さない。
    private func tidyReceiptImages() {
        let keep = Set(snapshot.expenses.compactMap(\.receiptImageID))
        let pending = Set(snapshot.pendingReceiptImageIDs)
        Task { [receiptImages] in
            await receiptImages.tidy(keeping: keep, protecting: pending)
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
                ? (member.role == .owner ? "そら" : "つばさ")
                : name
            return cleaned
        }
        if let categoryBudgets {
            household.categoryBudgets = CategoryBudget.normalized(categoryBudgets)
        }
        await saveHousehold(household)
    }

    // MARK: - 覚えた店

    /// レシートから作った支出が保存されたときに、その店を覚える。
    ///
    /// 読み取りが「写北名古屋」と出しても、人が「Selfix北名古屋」に直して保存すれば、
    /// 次から同じ店のレシートは最初から正しく出る。相手の端末にも同期される。
    func rememberMerchant(key: String, merchant: String, category: ExpenseCategory) async {
        guard var household = snapshot.household else { return }
        let updated = MerchantMemory.remembering(
            household.merchantMemos,
            key: key,
            merchant: merchant,
            category: category
        )
        guard updated != household.merchantMemos else { return }
        household.merchantMemos = updated
        await saveHousehold(household)
    }

    /// 間違って覚えた店を忘れる。
    ///
    /// 覚え直すには同じ店のレシートをもう一度撮るしかない、では詰むため、
    /// 画面から消せるようにしておく。
    func forgetMerchant(key: String) async {
        guard var household = snapshot.household else { return }
        let updated = household.merchantMemos.filter { $0.key != key }
        guard updated.count != household.merchantMemos.count else { return }
        household.merchantMemos = updated
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

    /// 合言葉を発行して相手を招く。共有の用意と合言葉の発行をまとめて行う。
    func startSharingWithCode() async {
        guard var household = snapshot.household else { return }
        isPreparingInvite = true
        syncState = .syncing
        defer { isPreparingInvite = false }

        do {
            let result = try await cloudService.prepareShare(
                household: household,
                expenses: snapshot.expenses,
                incomes: snapshot.incomes
            )
            household.cloudLocation = result.0
            snapshot.household = household
            await persistLocally()

            guard let url = result.1.url else {
                throw CloudKitSyncService.SyncError.inviteUnavailable
            }
            shareInvite = try await cloudService.publishInvite(shareURL: url)
            syncState = .synced(.now)
        } catch {
            syncState = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    /// 相手からもらった合言葉で共有に参加する。
    @discardableResult
    func joinSharing(code: String) async -> Bool {
        isPreparingInvite = true
        syncState = .syncing
        defer { isPreparingInvite = false }

        do {
            let invite = try await cloudService.resolveInvite(code: code)
            let location = try await cloudService.acceptShare(at: invite.shareURL)
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
            // 一度使った合言葉は残さない。
            await cloudService.consumeInvite(code: invite.code)
            syncState = .synced(.now)
            return true
        } catch {
            syncState = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
            return false
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

            // まだ送れていないレシート画像を送り直す。
            for imageID in snapshot.pendingReceiptImageIDs {
                guard let expense = snapshot.expenses.first(where: { $0.receiptImageID == imageID }) else {
                    snapshot.pendingReceiptImageIDs.removeAll { $0 == imageID }
                    continue
                }
                do {
                    try await receiptImages.upload(
                        id: imageID,
                        expenseID: expense.id,
                        household: household
                    )
                    snapshot.pendingReceiptImageIDs.removeAll { $0 == imageID }
                } catch {
                    // 1枚送れなくても、家計のデータの同期は止めない。次の同期でまた試す。
                    continue
                }
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

            // 消えた支出のぶんは、もう送る必要がない。
            let liveImageIDs = Set(snapshot.expenses.compactMap(\.receiptImageID))
            snapshot.pendingReceiptImageIDs.removeAll { !liveImageIDs.contains($0) }
            await persistLocally()
            syncState = .synced(.now)
        } catch {
            syncState = .failed(error.localizedDescription)
        }

        // 相手が追加したひな形の分も、この端末で計上しておく。
        await applyRecurringExpenses()
        tidyReceiptImages()
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
            await receiptImages.removeAll()
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
