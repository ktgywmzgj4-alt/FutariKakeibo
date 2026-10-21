@preconcurrency import CloudKit
import Foundation
import UIKit

@MainActor
final class AppStore: ObservableObject {
    /// アプリ全体で1つ。画面のほか、通知を押したとき（`AppDelegate`）からも使う。
    static let shared = AppStore()

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
    /// 画面に出していた合言葉が使われた（相手が参加した）。共有の画面でお知らせを出す。
    @Published private(set) var inviteWasUsed = false
    /// 共有に参加している人（`loadShareMembers`）。共有していない・まだ読んでいないなら nil。
    @Published private(set) var shareMembers: [CloudKitSyncService.ShareMember]?
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
        /// iCloudに家計簿が2つ以上ある。どれに戻るかを利用者に選んでもらう（`recoveryCandidates`）。
        case chooseOne
        case failed(String)
    }

    @Published var isRecovering = false
    @Published var recoveryOutcome: RecoveryOutcome?
    @Published private(set) var recoveryCandidates: [RecoveryCandidate] = []
    /// 選ぶ画面に出しているあいだ、取ってきた中身を持っておく（選んだあとに取り直さない）。
    private var recoverySnapshots: [String: CloudKitSyncService.CloudSnapshot] = [:]

    /// iCloudに残っている家計簿を探して取り戻す。
    ///
    /// **アプリを消して入れ直すと、合言葉を発行した側は家計簿に戻れなかった。**
    /// 参加した側は合言葉をもう一度入れれば `joinSharing` が全部取り直すが、
    /// 発行した側は入れる合言葉を持たない。合言葉は使い切りだからだ。
    /// iCloudにデータはあるのに手元から届かない、という状態だった。
    ///
    /// **見つかった家計簿が2つ以上なら、どれに戻るかを選んでもらう。**
    /// 以前は自分で作ったほうを必ず選んでいたので、参加する前に一度でも合言葉を発行した人は、
    /// 相手との家計簿ではなく、そのとき作った古い家計簿に戻っていた（2026-10-19 監査）。
    /// 「取り戻せました」と出るのに、いつもの家計簿ではない、という状態になる。
    ///
    /// **自動では動かさない。** 起動時にCloudKitを触ると、entitlementの無いビルドで
    /// アプリごと落ちる（`loadIfNeeded` のコメント）。押した人がいるときだけ動く。
    func recoverHouseholdFromCloud() async {
        guard snapshot.household == nil, !isRecovering else { return }
        isRecovering = true
        recoveryOutcome = nil
        recoveryCandidates = []
        recoverySnapshots = [:]
        defer { isRecovering = false }

        do {
            let locations = try await cloudService.findExistingHouseholdLocations()
            guard !locations.isEmpty else {
                recoveryOutcome = .nothingFound
                return
            }
            var found: [(location: CloudLocation, cloud: CloudKitSyncService.CloudSnapshot)] = []
            var firstError: Error?
            for location in locations {
                do {
                    let cloud = try await cloudService.fetchSnapshot(at: location)
                    found.append((location, cloud))
                } catch {
                    // 1つ読めなくても、ほかの家計簿には戻れる。全部だめなときだけ失敗にする。
                    firstError = firstError ?? error
                }
            }
            guard !found.isEmpty else {
                throw firstError ?? CloudKitSyncService.SyncError.missingRootRecord
            }
            if found.count == 1, let only = found.first {
                await restore(only.cloud, at: only.location)
                return
            }
            for item in found {
                recoverySnapshots[RecoveryCandidate.key(for: item.location)] = item.cloud
            }
            recoveryCandidates = RecoveryCandidate.ranked(found.map {
                RecoveryCandidate(
                    location: $0.location,
                    household: $0.cloud.household,
                    expenses: $0.cloud.expenses,
                    incomes: $0.cloud.incomes
                )
            })
            recoveryOutcome = .chooseOne
        } catch {
            syncState = .localOnly
            recoveryOutcome = .failed(Self.inviteFailureMessage(
                for: error,
                fallback: "iCloudに繋がりませんでした。電波の届くところでもう一度お試しください。"
            ))
        }
    }

    /// 選ぶ画面で選ばれた家計簿に戻る。
    func recover(_ candidate: RecoveryCandidate) async {
        guard snapshot.household == nil, !isRecovering else { return }
        isRecovering = true
        defer { isRecovering = false }
        do {
            let cloud: CloudKitSyncService.CloudSnapshot
            if let cached = recoverySnapshots[candidate.id] {
                cloud = cached
            } else {
                cloud = try await cloudService.fetchSnapshot(at: candidate.location)
            }
            await restore(cloud, at: candidate.location)
        } catch {
            recoveryOutcome = .failed(Self.inviteFailureMessage(
                for: error,
                fallback: "iCloudに繋がりませんでした。電波の届くところでもう一度お試しください。"
            ))
        }
    }

    private func restore(_ cloud: CloudKitSyncService.CloudSnapshot, at location: CloudLocation) async {
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
        recoveryCandidates = []
        recoverySnapshots = [:]
        recoveryOutcome = .recovered
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
    /// 直さずに保存された店は、同じ内容で2回保存されるまで読み取りより優先しない
    /// （`MerchantMemory.remembering`）。
    func rememberMerchant(_ observation: MerchantObservation) async {
        guard var household = snapshot.household else { return }
        let updated = MerchantMemory.remembering(household.merchantMemos, observation)
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

    /// ある店で覚えた品の1件を忘れる。
    ///
    /// 間違って直した品を、同じ店のレシートを撮り直さずに消せるようにする。
    func forgetItemNote(shopKey: String, noteKey: String) async {
        guard var household = snapshot.household else { return }
        let updated = MerchantMemory.forgettingItemNote(household.merchantMemos, shopKey: shopKey, noteKey: noteKey)
        guard updated != household.merchantMemos else { return }
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
        guard var household = snapshot.household else { return }
        // 人が直した名前なので、確かな店になる（`MerchantMemory.renaming`）。
        let updated = MerchantMemory.renaming(household.merchantMemos, key: key, to: merchant)
        guard updated != household.merchantMemos else { return }
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
            let invite = try await cloudService.publishInvite(shareURL: url)
            shareInvite = invite
            inviteWasUsed = false
            // 控えに足す。前に発行した合言葉は、後片付け（`tidyIssuedInvites`）で
            // 公開データベースから消す（共有のURLが入っているので残さない）。
            snapshot.issuedInvites.append(IssuedInvite(code: invite.code, expiresAt: invite.expiresAt))
            await persistLocally()
            syncState = .synced(.now)
            Task { await tidyIssuedInvites() }
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
            // **参加する前に、合言葉を自分のものにする（「使われた印」を作る）。** 合言葉は1回だけ。
            // 発行した人にしか合言葉を消せないので、印が無いと期限まで誰でも使えてしまう。
            // 先に印を作れた1人だけが進める。参加に失敗しても、同じ人ならもう一度入れる。
            try await cloudService.claimInvite(invite)
            let location = try await cloudService.acceptShare(at: invite.shareURL)
            let cloud = try await cloudService.fetchSnapshot(at: location)

            // この端末が前に発行した合言葉（自分の前の家計簿のもの）は、もう要らない。
            // 控えだけ引き継いで、後片付けで公開データベースから消す。
            let leftoverInvites = snapshot.issuedInvites
            snapshot = Self.snapshotAfterJoining(current: snapshot, cloud: cloud, at: location)
            shareInvite = nil
            await persistLocally()
            syncState = .synced(.now)
            if !leftoverInvites.isEmpty {
                Task { await withdrawAllIssuedInvites() }
            }
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

    /// 共有のリンクから届いた招待で、まだ参加していないもの（参加してよいか確かめている）。
    @Published private(set) var pendingShareInvitation: PendingShareInvitation?

    /// 確かめ中の招待。家計簿を作った人の名前は、iCloudが教えてくれるときだけ入る。
    struct PendingShareInvitation: Identifiable {
        let id = UUID()
        let metadata: CKShare.Metadata
        var ownerName: String?
    }

    /// 共有のリンク（iCloudの招待）を開いたときに参加する。
    ///
    /// **すでに家計簿がある人は、黙って置き換えない。** 参加すると手元の家計簿は共有先のものに
    /// 置き換わり、iPhoneの中だけの記録は消える。合言葉で参加する画面には注意書きがあるが、
    /// リンクから入る経路は確かめずに置き換えていた（2026-10-19 監査）。この共有は
    /// 「リンクを知っている人なら誰でも参加できる」形なので、知らない人から届いたリンクでも起きうる。
    /// 同じ家計簿のリンクを開き直しただけなら、置き換わるものが無いので確かめない。
    func acceptPendingShareIfNeeded() async {
        guard let metadata = CloudShareInbox.shared.take() else { return }
        if let household = snapshot.household,
           metadata.hierarchicalRootRecordID?.zoneID.zoneName != household.cloudLocation?.zoneName {
            pendingShareInvitation = PendingShareInvitation(
                metadata: metadata,
                ownerName: metadata.ownerIdentity.nameComponents.flatMap { components in
                    let text = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
                    return text.isEmpty ? nil : text
                }
            )
            return
        }
        await accept(metadata)
    }

    /// 確かめたうえで、届いていた招待に参加する。
    ///
    /// 招待は引数で受け取る。アラートは押されたあとに閉じる処理（`declinePendingShare`）も呼ぶので、
    /// プロパティから読むと、参加する前に消えていることがある。
    func confirmPendingShare(_ invitation: PendingShareInvitation) async {
        pendingShareInvitation = nil
        await accept(invitation.metadata)
    }

    /// 届いていた招待には参加しない。手元の家計簿はそのまま。
    func declinePendingShare() {
        pendingShareInvitation = nil
    }

    private func accept(_ metadata: CKShare.Metadata) async {
        isLoading = true
        syncState = .syncing
        defer { isLoading = false }

        do {
            let location = try await cloudService.acceptShare(metadata)
            let cloud = try await cloudService.fetchSnapshot(at: location)
            let leftoverInvites = snapshot.issuedInvites
            snapshot = Self.snapshotAfterJoining(current: snapshot, cloud: cloud, at: location)
            shareInvite = nil
            await persistLocally()
            syncState = .synced(.now)
            if !leftoverInvites.isEmpty {
                Task { await withdrawAllIssuedInvites() }
            }
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

    /// 引っ張って更新したとき（`walletRefreshable` から呼ぶ）。
    ///
    /// 30秒ごとの取得（`startPeriodicRefresh`）がちょうど走っていたら、新しく始めずに
    /// **それが終わるのを待つ**。終われば、それがいちばん新しい内容になっている。
    /// `refreshFromCloudIfConfigured` は同期中だとすぐ戻るので、そのまま呼ぶと
    /// 引っ張っても一瞬で終わり、何も起きなかったように見える。
    ///
    /// 待つ時間の上限は呼ぶ側（`PullToRefresh.timeout`）が決める。
    func refreshFromPull() async {
        guard syncState == .syncing else {
            await refreshFromCloudIfConfigured()
            return
        }
        while syncState == .syncing {
            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch {
                return
            }
        }
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
        // 同期の前から手元にあった支出（削除印も）。ここに無いものが「新しく届いた支出」（通知の候補）。
        let knownExpenseIDs = Set(snapshot.expenses.map(\.id)).union(snapshot.deletedExpenseIDs.keys)
        do {
            // 家計簿の設定はこの先でクラウド側にまるごと置き換わる。
            // 手元で変えた呼び名や予算を落とさないよう、これだけは先に送る。1往復で済む。
            try await cloudService.saveHousehold(household)

            let cloud = try await cloudService.fetchSnapshot(at: location)
            // 突き合わせの決まりは `SyncMerge` にまとめてある（削除印が勝つ・新しいほうが勝つ・
            // 送り直すのはiCloud側が古いものだけ）。場面ごとのテストは `SyncMergeTests`。
            let expenseMerge = SyncMerge.merge(
                local: snapshot.expenses,
                localDeletions: snapshot.deletedExpenseIDs,
                remote: cloud.expenses,
                remoteDeletions: cloud.deletedExpenseIDs
            )
            let incomeMerge = SyncMerge.merge(
                local: snapshot.incomes,
                localDeletions: snapshot.deletedIncomeIDs,
                remote: cloud.incomes,
                remoteDeletions: cloud.deletedIncomeIDs
            )
            let merged = expenseMerge.entries
            let deletions = expenseMerge.deletions
            let mergedIncomes = incomeMerge.entries
            let incomeDeletions = incomeMerge.deletions

            // iCloudに無い、またはiCloudのほうが古いものだけが送り直しの対象。
            // 前回の送信が通っていれば、ここはたいてい空になる。
            let staleExpenses = merged.filter { expenseMerge.staleIDs.contains($0.id) }
            let staleIncomes = mergedIncomes.filter { incomeMerge.staleIDs.contains($0.id) }
            let unsentDeletions = expenseMerge.unsentDeletions
            let unsentIncomeDeletions = incomeMerge.unsentDeletions

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
            // 手元に保存し終えてから知らせる。押したときにその支出を開けるように。
            await announcePartnerExpenses(
                knownBefore: knownExpenseIDs,
                merged: merged,
                creators: cloud.expenseCreators
            )

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
        // 発行した合言葉が残っていれば後片付けする。無ければ通信しない。
        if !snapshot.issuedInvites.isEmpty {
            await tidyIssuedInvites()
        }
        // 相手の支出の合図（CloudKitの購読）を通知の設定に合わせる。たいていは何もしない（1日に1回まで）。
        await updateExpenseSubscription()
    }

    /// 家計簿に入ったあとの手元の中身（合言葉からでも、共有のリンクからでも）。
    ///
    /// **同じ家計簿に入り直したときは、手元を置き換えずに突き合わせる。**
    /// 家計簿を作った人に共有をやめられて外れていたあいだに足した記録や、送れていなかった記録は、
    /// 手元にしか無い。置き換えるとそれが消える（同じ家計簿の合言葉をもう一度入れたときも同じ）。
    /// 突き合わせて残し、次の同期で送る。レシート画像の送信待ちも残す（2026-10-19 監査）。
    ///
    /// 家計簿の設定（名前・予算・覚えた店など）も、同じ家計簿なら新しいほうを残す。同期と同じ決まり
    /// （`CloudKitSyncService.upsertHousehold` は更新の新しいほうが丸ごと勝つ）。以前は iCloud 側で
    /// 置き換えていたので、外れていたあいだに変えた設定が消えていた（2026-10-21、T-048 の準備）。
    ///
    /// 別の家計簿に入ったときは、これまでどおり置き換える（参加する前に画面で伝えている）。
    /// 発行した合言葉の控えは、どちらでも引き継ぐ（後片付けで公開データベースから消すため）。
    nonisolated static func snapshotAfterJoining(
        current: AppSnapshot,
        cloud: CloudKitSyncService.CloudSnapshot,
        at location: CloudLocation
    ) -> AppSnapshot {
        let sameHousehold = Self.isSameHousehold(current.household, as: cloud.household, at: location)
        var household = cloud.household
        if sameHousehold, let local = current.household, local.updatedAt > household.updatedAt {
            household = local
        }
        household.cloudLocation = location
        let partner = household.members.first { $0.role == .partner }?.id ?? household.members.last?.id
        guard sameHousehold else {
            return AppSnapshot(
                household: household,
                selectedMemberID: partner,
                expenses: cloud.expenses,
                incomes: cloud.incomes,
                deletedExpenseIDs: cloud.deletedExpenseIDs,
                deletedIncomeIDs: cloud.deletedIncomeIDs,
                issuedInvites: current.issuedInvites
            )
        }

        let expenses = SyncMerge.merge(
            local: current.expenses,
            localDeletions: current.deletedExpenseIDs,
            remote: cloud.expenses,
            remoteDeletions: cloud.deletedExpenseIDs
        )
        let incomes = SyncMerge.merge(
            local: current.incomes,
            localDeletions: current.deletedIncomeIDs,
            remote: cloud.incomes,
            remoteDeletions: cloud.deletedIncomeIDs
        )
        // この端末の「自分」は、家計簿に残っていればそのまま。
        let me = current.selectedMemberID.flatMap { id in
            household.members.contains { $0.id == id } ? id : nil
        } ?? partner
        return AppSnapshot(
            household: household,
            selectedMemberID: me,
            expenses: expenses.entries,
            incomes: incomes.entries,
            deletedExpenseIDs: expenses.deletions,
            deletedIncomeIDs: incomes.deletions,
            pendingReceiptImageIDs: current.pendingReceiptImageIDs,
            issuedInvites: current.issuedInvites
        )
    }

    /// 入ろうとしている家計簿が、手元の家計簿と同じか。
    ///
    /// 同じ場所（ゾーン）なら同じ。**場所が違っても、家計簿のID（`Household.id`）が同じなら同じ**とみなす。
    /// 共有の形を移すときに、家計簿を別の場所へ写して共有し直す案がある（`Docs/SHARING_MIGRATION_PLAN.md`）。
    /// そのとき入り直すパートナーの手元にしか無い記録を、置き換えて消さないため。
    /// 別々に作った家計簿は、IDが違うので同じにはならない。
    nonisolated static func isSameHousehold(
        _ local: Household?,
        as joined: Household,
        at location: CloudLocation
    ) -> Bool {
        guard let local else { return false }
        if let localLocation = local.cloudLocation,
           RecoveryCandidate.key(for: localLocation) == RecoveryCandidate.key(for: location) {
            return true
        }
        return local.id == joined.id
    }

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

    /// 送り直しが要るものの印。中身は `SyncMerge.staleIDs`（テストはこの名前で呼んでいる）。
    nonisolated static func staleIDs(
        local: [(id: UUID, updatedAt: Date)],
        remote: [(id: UUID, updatedAt: Date)]
    ) -> Set<UUID> {
        SyncMerge.staleIDs(local: local, remote: remote)
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

    // MARK: - 合言葉の後片付けと、共有に参加している人

    /// この端末が発行した合言葉の後片付け。
    ///
    /// 合言葉のレコードには共有のURLが入っていて、**消せるのは発行した本人だけ**。
    /// 使われたもの・期限の切れたもの・発行し直して要らなくなったものを、公開データベースから消す。
    /// 通信できなければ控えを残し、次の同期でもう一度試す。
    func tidyIssuedInvites() async {
        let issued = snapshot.issuedInvites
        guard !issued.isEmpty else { return }
        let latestCode = IssuedInvite.latest(in: issued)?.code
        var finished: Set<String> = []
        for invite in issued {
            let isLatest = invite.code == latestCode
            var remote: ShareInvite.State?
            if IssuedInvite.needsRemoteCheck(invite, isLatest: isLatest) {
                remote = try? await cloudService.issuedInviteState(code: invite.code)
                if remote == nil { continue }
            }
            switch IssuedInvite.disposition(invite, isLatest: isLatest, remoteState: remote) {
            case .keep:
                continue
            case .forget:
                finished.insert(invite.code)
            case .withdraw:
                do {
                    try await cloudService.withdrawInvite(code: invite.code)
                    finished.insert(invite.code)
                } catch {
                    continue
                }
            }
            if remote == .used, shareInvite?.code == invite.code {
                shareInvite = nil
                inviteWasUsed = true
            } else if shareInvite?.code == invite.code {
                shareInvite = nil
            }
        }
        guard !finished.isEmpty else { return }
        // 待っているあいだに新しく発行した合言葉は消さない。片付いたものだけ外す。
        snapshot.issuedInvites.removeAll { finished.contains($0.code) }
        await persistLocally()
    }

    /// 発行した合言葉を、期限や使われたかに関わらず全部消す（別の家計簿に移ったとき・共有をやめたとき）。
    private func withdrawAllIssuedInvites() async {
        var finished: Set<String> = []
        for invite in snapshot.issuedInvites {
            if (try? await cloudService.withdrawInvite(code: invite.code)) != nil {
                finished.insert(invite.code)
            }
        }
        guard !finished.isEmpty else { return }
        snapshot.issuedInvites.removeAll { finished.contains($0.code) }
        await persistLocally()
    }

    /// 共有に参加している人を読む。共有の画面を開いたときに呼ぶ。
    ///
    /// 読めなかったときは前の結果を残し、アラートは出さない（通信が切れているだけのことが多い）。
    func loadShareMembers() async {
        guard let location = snapshot.household?.cloudLocation else {
            shareMembers = nil
            return
        }
        do {
            shareMembers = try await cloudService.shareMembers(at: location)
        } catch {
            // 前の結果を残す。
        }
    }

    /// 知らない人が参加していたときに、共有をやめる（家計簿を作った人だけ）。
    ///
    /// 家計簿のデータは消えない。パートナーも入れなくなるので、新しい合言葉で入り直してもらう。
    /// 共有を始め直しても共有のURLは前と同じ（Appleの説明）。使った合言葉ではもう入れないが、
    /// URLそのものを控えている人は入れてしまう（`CloudKitSyncService.stopSharing`）。
    @discardableResult
    func stopSharingBecauseOfStrangers() async -> Bool {
        guard let location = snapshot.household?.cloudLocation, location.scope == .privateDatabase else {
            return false
        }
        isPreparingInvite = true
        defer { isPreparingInvite = false }
        do {
            try await cloudService.stopSharing(at: location)
            shareInvite = nil
            inviteWasUsed = false
            shareMembers = nil
            await withdrawAllIssuedInvites()
            await loadShareMembers()
            return true
        } catch {
            errorMessage = Self.inviteFailureMessage(
                for: error,
                fallback: "共有をやめられませんでした。通信の状態を確かめて、もう一度お試しください。"
            )
            return false
        }
    }

    // MARK: - 相手の支出の通知（T-045・T-046）

    /// 通知を押して開く先。画面（`MainTabView`）が開いたら使って消す。
    enum NotificationRoute: Equatable, Sendable {
        case expense(UUID)
        /// 何件かまとめた通知。履歴を開く。
        case history
    }

    @Published var pendingNotificationRoute: NotificationRoute?
    /// 設定の「パートナーの支出を知らせる」。この端末だけの設定（相手には伝わらない）。
    @Published private(set) var notifyPartnerExpenses = UserDefaults.standard.bool(forKey: AppStore.notifyPartnerExpensesKey)
    @Published private(set) var notificationPermission: NotificationPermission = .notDetermined

    nonisolated static let notifyPartnerExpensesKey = "notifyPartnerExpenses"
    private static let announcedExpenseIDsKey = "announcedPartnerExpenseIDs"
    private let notifications = LocalNotifications()
    /// この利用者のユーザーレコードの名前。誰が登録した支出かを見分ける（初めて要るときに1回だけ聞く）。
    private var myUserRecordName: String?
    /// Appleに端末が登録でき、CloudKitの合図（サイレントプッシュ）を受け取れる（T-047）。
    /// 通知がOFFのとき、プッシュの権限（`aps-environment`）が無いビルドでは false のまま。
    private var canReceiveCloudKitPushes = false
    private static let subscribedScopeKey = "expenseChangesSubscriptionScope"
    private static let subscribedAtKey = "expenseChangesSubscribedAt"

    /// 知らせた支出の控え（端末だけ）。家計簿を置き換えても残す。同じ支出を2回知らせないため。
    private static var announcedExpenseIDs: [UUID] {
        get {
            (UserDefaults.standard.stringArray(forKey: announcedExpenseIDsKey) ?? []).compactMap { UUID(uuidString: $0) }
        }
        set {
            UserDefaults.standard.set(newValue.map(\.uuidString), forKey: announcedExpenseIDsKey)
        }
    }

    func refreshNotificationPermission() async {
        notificationPermission = await notifications.permission()
    }

    /// 設定の「パートナーの支出を知らせる」を切り替える。
    ///
    /// **通知の許可は、ここでONにしたときだけ求める**（起動したときには聞かない）。
    /// 許可されなければONにしない（設定の画面で、iPhoneの「設定」への案内を出す）。
    /// OFFにしても同期は続く。
    ///
    /// アプリを開いているあいだは同期（30秒ごと・開いたとき）で、閉じているあいだは CloudKit の合図
    /// （サイレントプッシュ）で同期して知らせる。合図はONのときだけ受ける（OFFなら購読を外す）。
    func setNotifyPartnerExpenses(_ isOn: Bool) async {
        if isOn {
            var permission = await notifications.permission()
            if permission == .notDetermined {
                permission = await notifications.requestPermission()
            }
            notificationPermission = permission
            guard permission == .allowed else {
                notifyPartnerExpenses = false
                UserDefaults.standard.set(false, forKey: Self.notifyPartnerExpensesKey)
                return
            }
        }
        notifyPartnerExpenses = isOn
        UserDefaults.standard.set(isOn, forKey: Self.notifyPartnerExpensesKey)
        if isOn {
            // CloudKitの合図を受けるための、Appleへの端末の登録。結果は `remoteNotificationsRegistered`。
            UIApplication.shared.registerForRemoteNotifications()
        }
        await updateExpenseSubscription()
    }

    /// Appleに端末が登録できた（`AppDelegate`）。CloudKitの合図を受けられるので、購読を置く。
    func remoteNotificationsRegistered() async {
        canReceiveCloudKitPushes = true
        guard UIApplication.shared.isProtectedDataAvailable else { return }
        await loadIfNeeded()
        await updateExpenseSubscription()
    }

    /// CloudKitの購読（相手の支出の合図）を、通知の設定と家計簿の置き場所に合わせる。決まりは `ExpenseSubscriptionPlan`。
    ///
    /// 読み込みの途中は何もしない（家計簿が見えないまま外さないため）。通信できなければ、次の同期でもう一度。
    func updateExpenseSubscription() async {
        guard didLoad, !isLoading else { return }
        let defaults = UserDefaults.standard
        let action = ExpenseSubscriptionPlan.action(
            notificationsOn: notifyPartnerExpenses,
            location: snapshot.household?.cloudLocation,
            subscribedScope: defaults.string(forKey: Self.subscribedScopeKey).flatMap { CloudLocation.Scope(rawValue: $0) },
            subscribedAt: defaults.object(forKey: Self.subscribedAtKey) as? Date,
            now: .now
        )
        do {
            switch action {
            case .keep:
                return
            case let .unsubscribe(scope):
                try await cloudService.unsubscribeFromExpenseChanges(in: scope)
                defaults.removeObject(forKey: Self.subscribedScopeKey)
                defaults.removeObject(forKey: Self.subscribedAtKey)
            case let .subscribe(scope):
                // 合図を受け取れない端末（登録の失敗・プッシュの権限の無いビルド）には置かない。
                guard canReceiveCloudKitPushes else { return }
                try await cloudService.subscribeToExpenseChanges(in: scope)
                defaults.set(scope.rawValue, forKey: Self.subscribedScopeKey)
                defaults.set(Date.now, forKey: Self.subscribedAtKey)
            case let .move(from: oldScope, to: newScope):
                guard canReceiveCloudKitPushes else { return }
                try? await cloudService.unsubscribeFromExpenseChanges(in: oldScope)
                try await cloudService.subscribeToExpenseChanges(in: newScope)
                defaults.set(newScope.rawValue, forKey: Self.subscribedScopeKey)
                defaults.set(Date.now, forKey: Self.subscribedAtKey)
            }
        } catch {
            // 次の同期・設定の切り替えでもう一度試す。
        }
    }

    /// CloudKitの合図（サイレントプッシュ）を受けたときの同期（T-047）。
    ///
    /// 合図は「変わった」という知らせだけで、中身は使わない。いつもの同期をして、相手の新しい支出があれば
    /// 同期の中で知らせる（`announcePartnerExpenses`）。**通知を受けたことと同期が終わったことは別**で、
    /// 知らせるのは手元に保存し終えてから。合図が届かなくても、次にアプリを開いたときの同期で追いつく。
    func refreshForCloudKitPush() async -> UIBackgroundFetchResult {
        // 端末のロックを一度も解いていないと、保存したファイルが読めない（`LocalSnapshotStore` の保護）。
        // 読めないまま読み込むと「読み込めませんでした」のまま止まるので、そのときは何もしない。
        guard UIApplication.shared.isProtectedDataAvailable else { return .failed }
        await loadIfNeeded()
        guard snapshot.household?.cloudLocation != nil else { return .noData }
        guard notifyPartnerExpenses else {
            // 通知をOFFにしたのに合図が残っていた（外すのに失敗していた）。もう一度外し、同期はしない。
            await updateExpenseSubscription()
            return .noData
        }
        let before = ChangeMark(snapshot)
        await refreshFromCloudIfConfigured()
        if case .failed = syncState { return .failed }
        return ChangeMark(snapshot) == before ? .noData : .newData
    }

    /// 同期の前後で何か変わったかを、安く見るための印（iOSに「新しいデータがあったか」を返すため）。
    private struct ChangeMark: Equatable {
        var expenseCount: Int
        var deletionCount: Int
        var latestUpdate: Date?

        init(_ snapshot: AppSnapshot) {
            expenseCount = snapshot.expenses.count
            deletionCount = snapshot.deletedExpenseIDs.count
            latestUpdate = snapshot.expenses.map(\.updatedAt).max()
        }
    }

    /// 相手が新しく登録した支出があれば、この端末で知らせる。決まりは `PartnerExpenseAlert`。
    private func announcePartnerExpenses(
        knownBefore: Set<UUID>,
        merged: [Expense],
        creators: [UUID: String]
    ) async {
        guard notifyPartnerExpenses else { return }
        let candidates = PartnerExpenseAlert.candidates(
            knownBefore: knownBefore,
            merged: merged,
            alreadyAnnounced: Set(Self.announcedExpenseIDs),
            now: .now
        )
        // 新しい支出が無ければ、ここで終わる（通信しない）。
        guard !candidates.isEmpty else { return }
        guard await notifications.permission() == .allowed else { return }
        if myUserRecordName == nil {
            myUserRecordName = try? await cloudService.currentUserRecordName()
        }
        let identity = PartnerExpenseAlert.Identity(
            placeholder: CKCurrentUserDefaultName,
            recordName: myUserRecordName
        )
        // 待っているあいだに別の同期が同じ支出を知らせていないか、控えを読み直してから決める。
        // ここから控えに書くまでは待たないので、2回知らせることはない。
        let toAnnounce = PartnerExpenseAlert.expensesToAnnounce(
            knownBefore: knownBefore,
            merged: candidates,
            creators: creators,
            identity: identity,
            alreadyAnnounced: Set(Self.announcedExpenseIDs),
            now: .now
        )
        guard let content = PartnerExpenseAlert.content(for: toAnnounce) else { return }
        Self.announcedExpenseIDs = PartnerExpenseAlert.remembering(
            toAnnounce.map(\.id),
            in: Self.announcedExpenseIDs
        )
        await notifications.post(content)
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
