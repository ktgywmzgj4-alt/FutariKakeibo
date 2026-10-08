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
    /// 前面にいる間だけ回している定期取得。止めるために持っている。
    private var periodicRefreshTask: Task<Void, Never>?

    /// 自分から取りに行く間隔。
    ///
    /// **相手が保存したことを知らせてくれる仕組み（`CKSubscription`）がまだ無い。**
    /// 無いので、アプリを開いたままにしていると相手の記録はいつまでも出てこなかった。
    /// 引っぱれば出てくるが、相手を待っているときに引っぱり続ける人はいない。
    ///
    /// 短くするほど電池と通信を使う。30秒は「相手の入力に気づくまで」としては
    /// 十分に短く、待っている人が数えてしまうほど長くはない、という判断。
    nonisolated static let periodicRefreshInterval: Duration = .seconds(30)

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
        // **ここでCloudKitを触らないでください。**
        // `CKContainer.default()` は iCloudのentitlementを持たないビルドで
        // `CKException` を投げ、**Objective-Cの例外なのでSwiftのcatchでは捕まらず**
        // プロセスごと終わります。起動時に呼ぶと、アプリが開いた瞬間に落ちます。
        // 一度ここに取り戻し処理を置いてテストが全滅しました（2026-10-04）。
        // 取り戻しは `recoverHouseholdFromCloud()` で、利用者がボタンを押したときだけ動かします。
        await applyRecurringExpenses()
        tidyReceiptImages()
    }

    /// 結果を画面に出すための状態。取り戻しはボタンから動かす。
    enum RecoveryOutcome: Equatable {
        case recovered
        case nothingFound
        case failed(String)
    }

    @Published var isRecovering = false
    @Published var recoveryOutcome: RecoveryOutcome?

    /// iCloudに残っている家計簿を探して取り戻す。
    ///
    /// **アプリを消して入れ直すと、合言葉を発行した側は家計簿に戻れなかった。**
    /// 参加した側は合言葉をもう一度入れれば `joinSharing` が全部取り直すが、
    /// 発行した側は入れる合言葉を持たない。合言葉は使い切りで消えるからだ。
    /// iCloudにデータはあるのに手元から届かない、という状態だった。
    ///
    /// **自動では動かさない。** 起動時にCloudKitを触ると、entitlementの無いビルドで
    /// アプリごと落ちる（`loadIfNeeded` のコメント）。押した人がいるときだけ動く。
    func recoverHouseholdFromCloud() async {
        guard snapshot.household == nil, !isRecovering else { return }
        isRecovering = true
        recoveryOutcome = nil
        defer { isRecovering = false }

        do {
            guard let location = try await cloudService.findExistingHouseholdLocation() else {
                recoveryOutcome = .nothingFound
                return
            }
            let cloud = try await cloudService.fetchSnapshot(at: location)
            var household = cloud.household
            household.cloudLocation = location
            // **どちら側として戻ってきたかで「自分」が変わる。**
            // プライベート側にあるのは自分で作った家計簿なので、自分は発行した側。
            // 共有側にあるのは相手から共有された家計簿なので、自分は参加した側。
            // ここを取り違えると、支出が相手の名前で記録されていく。
            let me = Self.memberOnThisPhone(
                after: location.scope,
                members: household.members,
                ownerMemberID: household.ownerMemberID
            )
            snapshot = AppSnapshot(
                household: household,
                selectedMemberID: me,
                expenses: cloud.expenses,
                incomes: cloud.incomes,
                deletedExpenseIDs: cloud.deletedExpenseIDs,
                deletedIncomeIDs: cloud.deletedIncomeIDs
            )
            await persistLocally()
            syncState = .synced(.now)
            recoveryOutcome = .recovered
        } catch {
            syncState = .localOnly
            recoveryOutcome = .failed(Self.inviteFailureMessage(
                for: error,
                fallback: "iCloudに繋がりませんでした。電波の届くところでもう一度お試しください。"
            ))
        }
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
        // 端末に書けた時点で記録は残る。**iCloudへの送信を画面に待たせない。**
        // 送れなくても `syncState` に出るし、次の同期でもう一度送る。
        Task { await upload(expense) }
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
        Task { await upload(changed) }
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
        // 画像はレシート1枚で数百KBある。回線が細いと送信だけで何秒もかかり、
        // 「支出を保存」を押してから画面が動くまでの待ち時間になっていた。
        // 端末には書けているので、送るのは後ろで続ける。
        Task {
            await upload(expense)
            await uploadReceiptImage(imageID, expenseID: expenseID)
        }
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

    /// 覚えた店の名前を直す。
    ///
    /// 忘れて覚え直すには同じ店のレシートをもう一度撮るしかない。
    /// 「ほぼ合っているが一文字違う」ときに、撮り直しを強いるのは重すぎる。
    ///
    /// **鍵（`key`）は変えない。** 鍵は登録番号や電話番号から作られていて、
    /// 同じ店かどうかを見分けているのはそちら。名前だけが人の読むもの。
    func renameMerchant(key: String, to merchant: String) async {
        let trimmed = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var household = snapshot.household else { return }
        guard let index = household.merchantMemos.firstIndex(where: { $0.key == key }),
              household.merchantMemos[index].merchant != trimmed
        else { return }

        household.merchantMemos[index].merchant = trimmed
        household.merchantMemos[index].updatedAt = .now
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
        guard var household = snapshot.household else {
            errorMessage = Self.inviteFailureMessage(for: nil)
            return
        }
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
                throw CloudKitSyncService.SyncError.inviteUnavailable("共有のURLが空でした")
            }
            shareInvite = try await cloudService.publishInvite(shareURL: url)
            syncState = .synced(.now)
        } catch {
            syncState = .failed(error.localizedDescription)
            errorMessage = Self.inviteFailureMessage(for: error)
        }
    }

    /// 合言葉のやりとりが失敗したときに画面に出す言葉。
    ///
    /// 中身の分かっている失敗は、そのまま出す。利用者に直せることがあるから
    /// （iCloudにサインインしていない、合言葉の期限が切れている、など）。
    /// それ以外はiCloud側の言葉が英語で出てしまうので、短い日本語に置き換える。
    nonisolated static func inviteFailureMessage(
        for error: Error?,
        fallback: String = "合言葉を発行できませんでした。もう一度お試しください。"
    ) -> String {
        guard let error else { return fallback }

        if let syncError = error as? CloudKitSyncService.SyncError,
           let description = syncError.errorDescription {
            return description
        }
        guard let cloudError = error as? CKError else { return fallback }
        switch cloudError.code {
        case .notAuthenticated, .managedAccountRestricted:
            return "iCloudにサインインしてから、もう一度お試しください。"
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
            return "iCloudにつながりませんでした。通信の状態を確かめて、もう一度お試しください。"
        case .quotaExceeded:
            return "iCloudの空き容量が足りません。空けてから、もう一度お試しください。"
        default:
            return fallback
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
            errorMessage = Self.inviteFailureMessage(
                for: error,
                fallback: "この合言葉では参加できませんでした。もう一度お試しください。"
            )
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

    /// 前面にいる間だけ、ときどき自分から取りに行きはじめる。
    ///
    /// `refreshFromCloudIfConfigured` はアプリが前面に戻ったときと、
    /// 画面を引っぱったときにしか動かない。つまり開いたまま置いておくと、
    /// 相手が足した記録は**いつまでも出てこない**。そこを埋める。
    ///
    /// **画面には何も出ない。** 取得は `errorMessage` を触らないので、
    /// 通信が切れていてもアラートは出ず、次の回に回るだけ。
    /// 設定画面の「同期済み ○○:○○」だけが静かに進む。
    ///
    /// 二重に回さない。すでに回っていれば何もしない。
    func startPeriodicRefresh() {
        guard periodicRefreshTask == nil else { return }
        periodicRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                // 先に待つ。前面に戻った直後は呼ぶ側がもう1回取りに行っているので、
                // ここで即座に取ると同じ往復を2回することになる。
                do {
                    try await Task.sleep(for: Self.periodicRefreshInterval)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                await self.refreshFromCloudIfConfigured()
            }
        }
    }

    /// 後ろに回ったら止める。
    /// 止めないと、閉じたアプリのために通信を続けることになる。
    func stopPeriodicRefresh() {
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
    }

    /// iCloudの内容を取り込んで、手元と突き合わせる。
    ///
    /// **取ってくるのが先。送り直しは後ろへ回す。**
    /// 以前はここで手元の支出・収入・削除・レシート画像を1件ずつ全部送り直してから
    /// 取得していた。7件あれば7往復で、相手の記録が画面に出るまで10秒以上かかっていた。
    /// 送り直しが本当に要るのは**クラウド側が古いものだけ**で、それは突き合わせの途中で分かる。
    func refreshFromCloudIfConfigured() async {
        guard let household = snapshot.household,
              let location = household.cloudLocation,
              syncState != .syncing
        else { return }

        syncState = .syncing
        do {
            // 家計簿の設定はこの先でクラウド側にまるごと置き換わる。
            // 手元で変えた呼び名や予算を落とさないよう、これだけは先に送る。1往復で済む。
            try await cloudService.saveHousehold(household)

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

            // クラウドに無い、またはクラウドのほうが古いものだけが送り直しの対象。
            // 前回の送信が通っていれば、ここはたいてい空になる。
            let staleExpenseIDs = Self.staleIDs(
                local: merged.map { ($0.id, $0.updatedAt) },
                remote: cloud.expenses.map { ($0.id, $0.updatedAt) }
            )
            let staleExpenses = merged.filter { staleExpenseIDs.contains($0.id) }
            let staleIncomeIDs = Self.staleIDs(
                local: mergedIncomes.map { ($0.id, $0.updatedAt) },
                remote: cloud.incomes.map { ($0.id, $0.updatedAt) }
            )
            let staleIncomes = mergedIncomes.filter { staleIncomeIDs.contains($0.id) }
            let unsentDeletions = deletions.filter { cloud.deletedExpenseIDs[$0.key] == nil }
            let unsentIncomeDeletions = incomeDeletions.filter {
                cloud.deletedIncomeIDs[$0.key] == nil
            }

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

            // ここから先は画面に出ている内容を変えない。待たせない。
            Task {
                await pushBack(
                    expenses: staleExpenses,
                    incomes: staleIncomes,
                    deletedExpenses: unsentDeletions,
                    deletedIncomes: unsentIncomeDeletions,
                    household: mergedHousehold
                )
            }
        } catch {
            syncState = .failed(error.localizedDescription)
        }

        // 相手が追加したひな形の分も、この端末で計上しておく。
        await applyRecurringExpenses()
        tidyReceiptImages()
    }

    /// 送り直しが要るものの印。**クラウドに無いか、クラウドのほうが古いものだけ。**
    ///
    /// ここを「全部」にすると、同期のたびに件数ぶんの往復が走り、相手の記録が
    /// 画面に出るまで何秒もかかる。実機で10秒を超えていたのがそれだった。
    /// 同じ時刻のものは送らない — 送っても中身が変わらないため。
    /// 取り戻したあと、この端末の「自分」を誰にするか。
    ///
    /// **どちら側として戻ってきたかで入れ替わる。**
    /// プライベート側にあるのは自分で作った家計簿なので、自分は発行した側（owner）。
    /// 共有側にあるのは相手から共有された家計簿なので、自分は参加した側。
    ///
    /// ここを取り違えると**支出が相手の名前で記録されていき**、精算額が狂う。
    /// 実機では気づくまで時間がかかるので、ここで縛っておく。
    nonisolated static func memberOnThisPhone(
        after scope: CloudLocation.Scope,
        members: [Member],
        ownerMemberID: UUID
    ) -> UUID? {
        switch scope {
        case .privateDatabase:
            members.first { $0.id == ownerMemberID }?.id ?? members.first?.id
        case .sharedDatabase:
            members.first { $0.id != ownerMemberID }?.id ?? members.first?.id
        }
    }

    nonisolated static func staleIDs(
        local: [(id: UUID, updatedAt: Date)],
        remote: [(id: UUID, updatedAt: Date)]
    ) -> Set<UUID> {
        let remoteByID = Dictionary(remote.map { ($0.id, $0.updatedAt) }) { first, _ in first }
        return Set(
            local
                .filter { item in
                    guard let remoteDate = remoteByID[item.id] else { return true }
                    return item.updatedAt > remoteDate
                }
                .map(\.id)
        )
    }

    /// 前回の送信が通らなかったぶんを送り直す。
    ///
    /// 画面はもう新しくなっているので、ここで失敗しても `syncState` は動かさない。
    /// 残ったものは次の同期でまた拾われる。
    private func pushBack(
        expenses: [Expense],
        incomes: [Income],
        deletedExpenses: [UUID: Date],
        deletedIncomes: [UUID: Date],
        household: Household
    ) async {
        for expense in expenses {
            try? await cloudService.saveExpense(expense, household: household)
        }
        for (id, deletedAt) in deletedExpenses {
            try? await cloudService.deleteExpense(id: id, deletedAt: deletedAt, household: household)
        }
        for income in incomes {
            try? await cloudService.saveIncome(income, household: household)
        }
        for (id, deletedAt) in deletedIncomes {
            try? await cloudService.deleteIncome(id: id, deletedAt: deletedAt, household: household)
        }

        // まだ送れていないレシート画像。1枚ずつ、送れたものから印を外す。
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
                continue
            }
        }
        await persistLocally()
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
