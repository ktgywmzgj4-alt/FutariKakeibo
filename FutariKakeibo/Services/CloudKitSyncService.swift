@preconcurrency import CloudKit
import Foundation

private final class LockedState<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ operation: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation(&value)
    }
}

actor CloudKitSyncService {
    enum SyncError: LocalizedError {
        case iCloudUnavailable
        case missingRootRecord
        case invalidRecord(String)
        case shareNotAccepted
        case inviteUnavailable
        case inviteNotFound
        case inviteExpired
        case receiptImageMissing

        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable:
                "iCloudにサインインしてから、もう一度お試しください。"
            case .missingRootRecord:
                "共有家計の基準データが見つかりませんでした。"
            case let .invalidRecord(name):
                "iCloud上のデータ（\(name)）を読み取れませんでした。"
            case .shareNotAccepted:
                "共有への参加を完了できませんでした。"
            case .inviteUnavailable:
                "合言葉を発行できませんでした。通信の状態を確かめて、もう一度お試しください。"
            case .inviteNotFound:
                "その合言葉は見つかりませんでした。入力を確かめるか、相手にもう一度発行してもらってください。"
            case .inviteExpired:
                "この合言葉は期限が切れています。相手にもう一度発行してもらってください。"
            case .receiptImageMissing:
                "レシート画像をiCloudから取得できませんでした。通信の状態を確かめて、もう一度お試しください。"
            }
        }
    }

    struct CloudSnapshot: Sendable {
        var household: Household
        var expenses: [Expense]
        var incomes: [Income]
        var deletedExpenseIDs: [UUID: Date]
        var deletedIncomeIDs: [UUID: Date]
    }

    private nonisolated let explicitContainer: CKContainer?

    init(container: CKContainer? = nil) {
        explicitContainer = container
    }

    // CKContainer.default() は、iCloudのentitlementを持たないビルド
    // （署名なしでシミュレータへ入れた場合など）でCKExceptionを投げ、
    // 捕まえられないままプロセスごと終了する。起動時に必ず作るのをやめ、
    // 実際にCloudKitを使う時まで生成を遅らせる。
    nonisolated var container: CKContainer {
        explicitContainer ?? .default()
    }

    func accountStatus() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    func prepareShare(
        household: Household,
        expenses: [Expense],
        incomes: [Income] = []
    ) async throws -> (CloudLocation, CKShare) {
        guard try await accountStatus() == .available else {
            throw SyncError.iCloudUnavailable
        }

        let location = CloudLocation(
            scope: .privateDatabase,
            zoneName: "household-\(household.id.uuidString.lowercased())",
            ownerName: CKCurrentUserDefaultName,
            rootRecordName: "household-\(household.id.uuidString.lowercased())"
        )
        let database = container.privateCloudDatabase
        let zoneID = zoneID(for: location)
        try await saveZoneIfNeeded(CKRecordZone(zoneID: zoneID), in: database)

        let rootRecord = try await upsertHousehold(household, at: location, in: database)
        for expense in expenses {
            try await upsertExpense(expense, householdRecordID: rootRecord.recordID, at: location, in: database)
        }
        for income in incomes {
            try await upsertIncome(income, householdRecordID: rootRecord.recordID, at: location, in: database)
        }

        if let shareReference = rootRecord.share {
            let existingRecord = try await fetchRecord(shareReference.recordID, from: database)
            guard let existingShare = existingRecord as? CKShare else {
                // すでに共有されている印はあるのに、その共有が読めなかった。
                // ここで新しい CKShare を作ると同じレコードを二重に共有することになり、
                // CloudKit が例外を投げてアプリごと落ちる。作らずに引き返す。
                throw SyncError.inviteUnavailable
            }
            return (location, existingShare)
        }

        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = "ふたり家計簿" as CKRecordValue
        // 合言葉を知っている相手が参加できるようにする。合言葉は期限つきの使い切り。
        share.publicPermission = .readWrite
        try await modifyRecords(saving: [rootRecord, share], deleting: [], in: database, atomically: true)
        // 共有のURLはサーバー側で割り当てられる。合言葉に載せるため、保存後に取り直す。
        if let saved = try await fetchRecord(share.recordID, from: database) as? CKShare {
            return (location, saved)
        }
        return (location, share)
    }

    func acceptShare(_ metadata: CKShare.Metadata) async throws -> CloudLocation {
        try await accept(metadata)
        guard let rootRecordID = metadata.hierarchicalRootRecordID else {
            throw SyncError.shareNotAccepted
        }
        return CloudLocation(
            scope: .sharedDatabase,
            zoneName: rootRecordID.zoneID.zoneName,
            ownerName: rootRecordID.zoneID.ownerName,
            rootRecordName: rootRecordID.recordName
        )
    }

    // MARK: - 合言葉

    /// 合言葉を公開データベースへ1件だけ置く。中身は共有の場所と失効時刻だけで、
    /// 家計のデータは一切入らない。
    func publishInvite(shareURL: URL) async throws -> ShareInvite {
        let database = container.publicCloudDatabase
        // まず当たらないが、万一同じ合言葉が残っていたら引き直す。
        for _ in 0..<5 {
            let code = ShareInvite.makeCode()
            let recordID = inviteRecordID(for: code)
            if try await fetchRecord(recordID, from: database) != nil { continue }

            let expiresAt = Date.now.addingTimeInterval(ShareInvite.lifetime)
            let record = CKRecord(recordType: RecordType.shareInvite, recordID: recordID)
            record["shareURL"] = shareURL.absoluteString as CKRecordValue
            record["expiresAt"] = expiresAt as CKRecordValue
            _ = try await saveRecord(record, to: database)
            return ShareInvite(code: code, shareURL: shareURL, expiresAt: expiresAt)
        }
        throw SyncError.inviteUnavailable
    }

    func resolveInvite(code: String) async throws -> ShareInvite {
        let cleaned = ShareInvite.normalized(code)
        guard cleaned.count == ShareInvite.codeLength else { throw SyncError.inviteNotFound }

        guard
            let record = try await fetchRecord(
                inviteRecordID(for: cleaned),
                from: container.publicCloudDatabase
            ),
            let urlText = record["shareURL"] as? String,
            let url = URL(string: urlText),
            let expiresAt = record["expiresAt"] as? Date
        else { throw SyncError.inviteNotFound }

        guard expiresAt > .now else { throw SyncError.inviteExpired }
        return ShareInvite(code: cleaned, shareURL: url, expiresAt: expiresAt)
    }

    /// 使い終えた合言葉は残さない。消せなくても参加は済んでいるので黙って進む。
    func consumeInvite(code: String) async {
        let recordID = inviteRecordID(for: ShareInvite.normalized(code))
        try? await deleteRecord(recordID, from: container.publicCloudDatabase)
    }

    /// 共有のURLから参加する。
    func acceptShare(at url: URL) async throws -> CloudLocation {
        let metadata = try await fetchShareMetadata(for: url)
        return try await acceptShare(metadata)
    }

    private func inviteRecordID(for code: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "invite-\(code)")
    }

    private func deleteRecord(_ id: CKRecord.ID, from database: CKDatabase) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            database.delete(withRecordID: id) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func fetchShareMetadata(for url: URL) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchShareMetadataOperation(shareURLs: [url])
            operation.shouldFetchRootRecord = false
            let found = LockedState<CKShare.Metadata?>(nil)
            operation.perShareMetadataResultBlock = { _, result in
                if case let .success(metadata) = result {
                    found.withLock { $0 = metadata }
                }
            }
            operation.fetchShareMetadataResultBlock = { result in
                switch result {
                case .success:
                    if let metadata = found.withLock({ $0 }) {
                        continuation.resume(returning: metadata)
                    } else {
                        continuation.resume(throwing: SyncError.inviteNotFound)
                    }
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
    }

    func fetchSnapshot(at location: CloudLocation) async throws -> CloudSnapshot {
        let database = database(for: location)
        let rootID = CKRecord.ID(recordName: location.rootRecordName, zoneID: zoneID(for: location))
        guard let root = try await fetchRecord(rootID, from: database) else {
            throw SyncError.missingRootRecord
        }
        var household = try decodeHousehold(root)
        household.cloudLocation = location

        let query = CKQuery(recordType: RecordType.expense, predicate: NSPredicate(value: true))
        let records = try await queryAll(query, zoneID: zoneID(for: location), in: database)
        var expenses: [Expense] = []
        var deletedExpenseIDs: [UUID: Date] = [:]
        for record in records {
            if (record["isDeleted"] as? NSNumber)?.boolValue == true {
                let deletion = try decodeDeletion(record)
                deletedExpenseIDs[deletion.id] = max(
                    deletedExpenseIDs[deletion.id] ?? .distantPast,
                    deletion.deletedAt
                )
            } else {
                expenses.append(try decodeExpense(record))
            }
        }
        expenses.sort { $0.date > $1.date }

        let incomeQuery = CKQuery(recordType: RecordType.income, predicate: NSPredicate(value: true))
        let incomeRecords = try await queryAll(incomeQuery, zoneID: zoneID(for: location), in: database)
        var incomes: [Income] = []
        var deletedIncomeIDs: [UUID: Date] = [:]
        for record in incomeRecords {
            if (record["isDeleted"] as? NSNumber)?.boolValue == true {
                let deletion = try decodeDeletion(record)
                deletedIncomeIDs[deletion.id] = max(
                    deletedIncomeIDs[deletion.id] ?? .distantPast,
                    deletion.deletedAt
                )
            } else {
                incomes.append(try decodeIncome(record))
            }
        }
        incomes.sort { $0.date > $1.date }

        return CloudSnapshot(
            household: household,
            expenses: expenses,
            incomes: incomes,
            deletedExpenseIDs: deletedExpenseIDs,
            deletedIncomeIDs: deletedIncomeIDs
        )
    }

    func saveHousehold(_ household: Household) async throws {
        guard let location = household.cloudLocation else { return }
        let database = database(for: location)
        _ = try await upsertHousehold(household, at: location, in: database)
    }

    func saveExpense(_ expense: Expense, household: Household) async throws {
        guard let location = household.cloudLocation else { return }
        let database = database(for: location)
        let rootID = CKRecord.ID(recordName: location.rootRecordName, zoneID: zoneID(for: location))
        try await upsertExpense(expense, householdRecordID: rootID, at: location, in: database)
    }

    func deleteExpense(id: UUID, deletedAt: Date, household: Household) async throws {
        guard let location = household.cloudLocation else { return }
        let database = database(for: location)
        let rootID = CKRecord.ID(recordName: location.rootRecordName, zoneID: zoneID(for: location))
        let recordID = CKRecord.ID(
            recordName: "expense-\(id.uuidString.lowercased())",
            zoneID: zoneID(for: location)
        )
        let record = try await fetchRecord(recordID, from: database)
            ?? CKRecord(recordType: RecordType.expense, recordID: recordID)
        if (record["isDeleted"] as? NSNumber)?.boolValue == true,
           let remoteDeletedAt = record["updatedAt"] as? Date,
           remoteDeletedAt >= deletedAt {
            return
        }
        record.parent = parentReference(to: rootID)
        record["id"] = id.uuidString as CKRecordValue
        record["isDeleted"] = NSNumber(value: true) as CKRecordValue
        record["updatedAt"] = deletedAt as CKRecordValue
        _ = try await saveRecord(record, to: database)
    }

    func saveIncome(_ income: Income, household: Household) async throws {
        guard let location = household.cloudLocation else { return }
        let database = database(for: location)
        let rootID = CKRecord.ID(recordName: location.rootRecordName, zoneID: zoneID(for: location))
        try await upsertIncome(income, householdRecordID: rootID, at: location, in: database)
    }

    func deleteIncome(id: UUID, deletedAt: Date, household: Household) async throws {
        guard let location = household.cloudLocation else { return }
        let database = database(for: location)
        let rootID = CKRecord.ID(recordName: location.rootRecordName, zoneID: zoneID(for: location))
        let recordID = CKRecord.ID(
            recordName: "income-\(id.uuidString.lowercased())",
            zoneID: zoneID(for: location)
        )
        let record = try await fetchRecord(recordID, from: database)
            ?? CKRecord(recordType: RecordType.income, recordID: recordID)
        if (record["isDeleted"] as? NSNumber)?.boolValue == true,
           let remoteDeletedAt = record["updatedAt"] as? Date,
           remoteDeletedAt >= deletedAt {
            return
        }
        record.parent = parentReference(to: rootID)
        record["id"] = id.uuidString as CKRecordValue
        record["isDeleted"] = NSNumber(value: true) as CKRecordValue
        record["updatedAt"] = deletedAt as CKRecordValue
        _ = try await saveRecord(record, to: database)
    }

    // MARK: - レシート画像

    /// レシート画像を1枚、家計と同じゾーンへ置く。
    ///
    /// 画像は `CKAsset`（別置きのファイル）として持つ。支出のレコードには入れない。
    /// こうすると支出の読み書きは軽いままで、画像は見るときだけ落ちてくる。
    /// 親を家計のレコードにしてあるので、共有に参加した相手も同じ画像を見られる。
    func saveReceiptImage(
        id: UUID,
        expenseID: UUID,
        displayFileURL: URL,
        thumbnailFileURL: URL?,
        household: Household
    ) async throws {
        guard let location = household.cloudLocation else { return }
        let database = database(for: location)
        let rootID = CKRecord.ID(recordName: location.rootRecordName, zoneID: zoneID(for: location))
        let recordID = receiptRecordID(for: id, at: location)
        let record = try await fetchRecord(recordID, from: database)
            ?? CKRecord(recordType: RecordType.receiptImage, recordID: recordID)

        // レシート画像は撮ったあと変わらない。すでに載っているなら送り直さない。
        if record["asset"] as? CKAsset != nil { return }

        record.parent = parentReference(to: rootID)
        record["id"] = id.uuidString as CKRecordValue
        record["expenseID"] = expenseID.uuidString as CKRecordValue
        record["asset"] = CKAsset(fileURL: displayFileURL)
        if let thumbnailFileURL {
            record["thumbnail"] = CKAsset(fileURL: thumbnailFileURL)
        }
        record["createdAt"] = Date.now as CKRecordValue
        _ = try await saveRecord(record, to: database)
    }

    /// 相手が撮ったレシートを取ってくる。詳細画面を開いたときだけ呼ばれる。
    func fetchReceiptImage(
        id: UUID,
        expenseID: UUID,
        household: Household
    ) async throws -> (display: Data, thumbnail: Data?) {
        guard let location = household.cloudLocation else {
            throw SyncError.receiptImageMissing
        }
        let database = database(for: location)
        guard let record = try await fetchRecord(receiptRecordID(for: id, at: location), from: database) else {
            throw SyncError.receiptImageMissing
        }
        // 別の支出の画像を取り違えない。
        if let owner = record["expenseID"] as? String, owner != expenseID.uuidString {
            throw SyncError.receiptImageMissing
        }
        guard
            let asset = record["asset"] as? CKAsset,
            let fileURL = asset.fileURL,
            let display = try? Data(contentsOf: fileURL)
        else {
            throw SyncError.receiptImageMissing
        }
        let thumbnail = (record["thumbnail"] as? CKAsset)?.fileURL
            .flatMap { try? Data(contentsOf: $0) }
        return (display, thumbnail)
    }

    /// 支出を消したときに、その支出の画像も消す。
    ///
    /// 画像のIDは撮るたびに新しく作られ、**支出1件からしか参照されない**。
    /// レコード名にそのIDが入っているので、ここで消して相手の別の画像に当たることはない。
    func deleteReceiptImage(id: UUID, expenseID: UUID, household: Household) async throws {
        guard let location = household.cloudLocation else { return }
        let database = database(for: location)
        do {
            try await deleteRecord(receiptRecordID(for: id, at: location), from: database)
        } catch let error as CKError where error.code == .unknownItem {
            // もう無いなら、それでよい。
            return
        }
    }

    private func receiptRecordID(for id: UUID, at location: CloudLocation) -> CKRecord.ID {
        CKRecord.ID(
            recordName: "receipt-\(id.uuidString.lowercased())",
            zoneID: zoneID(for: location)
        )
    }

    // MARK: - Record mapping

    private enum RecordType {
        static let household = "Household"
        static let expense = "Expense"
        static let income = "Income"
        static let shareInvite = "ShareInvite"
        static let receiptImage = "ReceiptImage"
    }

    /// 支出・収入・レシート画像を、家計のレコードの「子」にする印。
    /// この親子関係があるから、相手を招いたときに家計まるごとが相手に渡る。
    ///
    /// **参照の種類は必ず `.none` にする。**
    /// Appleの決まりで、`parent` に `.deleteSelf` を入れると CloudKit が例外を投げる。
    /// Objective-Cの例外なので Swift の `catch` では捕まえられず、**アプリごと落ちる**。
    ///
    /// 共有を始めるまで `cloudLocation` は空で、保存はどれも入口で引き返す。
    /// つまりこの行が初めて動くのは合言葉を発行したときで、そこだけが落ちていた。
    ///
    /// 親を消したら子も消える動きは無くなるが、家計のレコードを消すことはなく、
    /// やめるときはゾーンごと消すので、実際に困る場面はない。
    private func parentReference(to recordID: CKRecord.ID) -> CKRecord.Reference {
        CKRecord.Reference(recordID: recordID, action: .none)
    }

    private func upsertHousehold(
        _ household: Household,
        at location: CloudLocation,
        in database: CKDatabase
    ) async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: location.rootRecordName, zoneID: zoneID(for: location))
        let record = try await fetchRecord(recordID, from: database)
            ?? CKRecord(recordType: RecordType.household, recordID: recordID)

        if let remoteUpdatedAt = record["updatedAt"] as? Date,
           remoteUpdatedAt > household.updatedAt {
            return record
        }

        record["id"] = household.id.uuidString as CKRecordValue
        record["name"] = household.name as CKRecordValue
        record["monthlyBudget"] = Int64(household.monthlyBudget) as CKRecordValue
        record["ownerMemberID"] = household.ownerMemberID.uuidString as CKRecordValue
        record["membersData"] = try JSONEncoder().encode(household.members) as CKRecordValue
        record["categoryBudgetsData"] = try JSONEncoder().encode(household.categoryBudgets) as CKRecordValue
        record["recurringExpensesData"] = try JSONEncoder().encode(household.recurringExpenses) as CKRecordValue
        record["merchantMemosData"] = try JSONEncoder().encode(household.merchantMemos) as CKRecordValue
        record["createdAt"] = household.createdAt as CKRecordValue
        record["updatedAt"] = household.updatedAt as CKRecordValue
        return try await saveRecord(record, to: database)
    }

    private func upsertExpense(
        _ expense: Expense,
        householdRecordID: CKRecord.ID,
        at location: CloudLocation,
        in database: CKDatabase
    ) async throws {
        let recordID = CKRecord.ID(
            recordName: "expense-\(expense.id.uuidString.lowercased())",
            zoneID: zoneID(for: location)
        )
        let record = try await fetchRecord(recordID, from: database)
            ?? CKRecord(recordType: RecordType.expense, recordID: recordID)
        // 削除印は古いオフライン端末からの再アップロードより常に優先する。
        guard (record["isDeleted"] as? NSNumber)?.boolValue != true else {
            return
        }
        if let remoteUpdatedAt = record["updatedAt"] as? Date,
           remoteUpdatedAt > expense.updatedAt {
            return
        }
        record.parent = parentReference(to: householdRecordID)
        record["id"] = expense.id.uuidString as CKRecordValue
        record["isDeleted"] = NSNumber(value: false) as CKRecordValue
        record["title"] = expense.title as CKRecordValue
        record["amount"] = Int64(expense.amount) as CKRecordValue
        record["date"] = expense.date as CKRecordValue
        record["category"] = expense.category.rawValue as CKRecordValue
        record["paidByMemberID"] = expense.paidByMemberID.uuidString as CKRecordValue
        record["splitMethod"] = expense.splitMethod.rawValue as CKRecordValue
        record["note"] = expense.note as CKRecordValue
        record["merchant"] = (expense.merchant ?? "") as CKRecordValue
        // レシート画像そのものは別のレコード（ReceiptImage）にある。ここに持つのは参照だけ。
        record["receiptImageID"] = (expense.receiptImageID?.uuidString ?? "") as CKRecordValue
        // 定期支出から作られた回かどうかは後から変わらないため、ある場合だけ書き込む。
        if let recurringID = expense.recurringID {
            record["recurringID"] = recurringID.uuidString as CKRecordValue
        }
        record["createdAt"] = expense.createdAt as CKRecordValue
        record["updatedAt"] = expense.updatedAt as CKRecordValue
        _ = try await saveRecord(record, to: database)
    }

    private func decodeHousehold(_ record: CKRecord) throws -> Household {
        guard
            let idText = record["id"] as? String,
            let id = UUID(uuidString: idText),
            let name = record["name"] as? String,
            let budgetNumber = record["monthlyBudget"] as? NSNumber,
            let ownerText = record["ownerMemberID"] as? String,
            let ownerID = UUID(uuidString: ownerText),
            let membersData = record["membersData"] as? Data,
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw SyncError.invalidRecord(record.recordID.recordName)
        }
        let members = try JSONDecoder().decode([Member].self, from: membersData)
        // 旧バージョンが作ったレコードにはこの2つの項目がないため、無い場合は空として扱う。
        let categoryBudgets = try (record["categoryBudgetsData"] as? Data)
            .map { try JSONDecoder().decode([CategoryBudget].self, from: $0) } ?? []
        let recurringExpenses = try (record["recurringExpensesData"] as? Data)
            .map { try JSONDecoder().decode([RecurringExpense].self, from: $0) } ?? []
        let merchantMemos = try (record["merchantMemosData"] as? Data)
            .map { try JSONDecoder().decode([MerchantMemo].self, from: $0) } ?? []
        return Household(
            id: id,
            name: name,
            monthlyBudget: budgetNumber.intValue,
            members: members,
            ownerMemberID: ownerID,
            categoryBudgets: categoryBudgets,
            recurringExpenses: recurringExpenses,
            merchantMemos: merchantMemos,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func decodeExpense(_ record: CKRecord) throws -> Expense {
        guard
            let idText = record["id"] as? String,
            let id = UUID(uuidString: idText),
            let title = record["title"] as? String,
            let amountNumber = record["amount"] as? NSNumber,
            let date = record["date"] as? Date,
            let categoryText = record["category"] as? String,
            let category = ExpenseCategory(rawValue: categoryText),
            let paidByText = record["paidByMemberID"] as? String,
            let paidByID = UUID(uuidString: paidByText),
            let splitText = record["splitMethod"] as? String,
            let splitMethod = Expense.SplitMethod(rawValue: splitText),
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw SyncError.invalidRecord(record.recordID.recordName)
        }

        return Expense(
            id: id,
            title: title,
            amount: amountNumber.intValue,
            date: date,
            category: category,
            paidByMemberID: paidByID,
            splitMethod: splitMethod,
            note: record["note"] as? String ?? "",
            merchant: record["merchant"] as? String,
            recurringID: (record["recurringID"] as? String).flatMap(UUID.init(uuidString:)),
            receiptImageID: (record["receiptImageID"] as? String).flatMap(UUID.init(uuidString:)),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func decodeDeletion(_ record: CKRecord) throws -> (id: UUID, deletedAt: Date) {
        guard
            let idText = record["id"] as? String,
            let id = UUID(uuidString: idText),
            let deletedAt = record["updatedAt"] as? Date
        else {
            throw SyncError.invalidRecord(record.recordID.recordName)
        }
        return (id, deletedAt)
    }

    private func upsertIncome(
        _ income: Income,
        householdRecordID: CKRecord.ID,
        at location: CloudLocation,
        in database: CKDatabase
    ) async throws {
        let recordID = CKRecord.ID(
            recordName: "income-\(income.id.uuidString.lowercased())",
            zoneID: zoneID(for: location)
        )
        let record = try await fetchRecord(recordID, from: database)
            ?? CKRecord(recordType: RecordType.income, recordID: recordID)
        // 削除印は古いオフライン端末からの再アップロードより常に優先する。
        guard (record["isDeleted"] as? NSNumber)?.boolValue != true else {
            return
        }
        if let remoteUpdatedAt = record["updatedAt"] as? Date,
           remoteUpdatedAt > income.updatedAt {
            return
        }
        record.parent = parentReference(to: householdRecordID)
        record["id"] = income.id.uuidString as CKRecordValue
        record["isDeleted"] = NSNumber(value: false) as CKRecordValue
        record["title"] = income.title as CKRecordValue
        record["amount"] = Int64(income.amount) as CKRecordValue
        record["date"] = income.date as CKRecordValue
        record["source"] = income.source.rawValue as CKRecordValue
        record["receivedByMemberID"] = income.receivedByMemberID.uuidString as CKRecordValue
        record["note"] = income.note as CKRecordValue
        record["createdAt"] = income.createdAt as CKRecordValue
        record["updatedAt"] = income.updatedAt as CKRecordValue
        _ = try await saveRecord(record, to: database)
    }

    private func decodeIncome(_ record: CKRecord) throws -> Income {
        guard
            let idText = record["id"] as? String,
            let id = UUID(uuidString: idText),
            let title = record["title"] as? String,
            let amountNumber = record["amount"] as? NSNumber,
            let date = record["date"] as? Date,
            let sourceText = record["source"] as? String,
            let source = IncomeSource(rawValue: sourceText),
            let receivedByText = record["receivedByMemberID"] as? String,
            let receivedByID = UUID(uuidString: receivedByText),
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            throw SyncError.invalidRecord(record.recordID.recordName)
        }

        return Income(
            id: id,
            title: title,
            amount: amountNumber.intValue,
            date: date,
            source: source,
            receivedByMemberID: receivedByID,
            note: record["note"] as? String ?? "",
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - CloudKit wrappers

    private func database(for location: CloudLocation) -> CKDatabase {
        switch location.scope {
        case .privateDatabase: container.privateCloudDatabase
        case .sharedDatabase: container.sharedCloudDatabase
        }
    }

    private func zoneID(for location: CloudLocation) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: location.zoneName, ownerName: location.ownerName)
    }

    private func saveZoneIfNeeded(_ zone: CKRecordZone, in database: CKDatabase) async throws {
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecordZone, Error>) in
            database.save(zone) { savedZone, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let savedZone {
                    continuation.resume(returning: savedZone)
                } else {
                    continuation.resume(throwing: SyncError.invalidRecord(zone.zoneID.zoneName))
                }
            }
        }
    }

    private func fetchRecord(_ id: CKRecord.ID, from database: CKDatabase) async throws -> CKRecord? {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                database.fetch(withRecordID: id) { record, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: record)
                    }
                }
            }
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func saveRecord(_ record: CKRecord, to database: CKDatabase) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            database.save(record) { savedRecord, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let savedRecord {
                    continuation.resume(returning: savedRecord)
                } else {
                    continuation.resume(throwing: SyncError.invalidRecord(record.recordID.recordName))
                }
            }
        }
    }

    private func modifyRecords(
        saving records: [CKRecord],
        deleting recordIDs: [CKRecord.ID],
        in database: CKDatabase,
        atomically: Bool
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: recordIDs)
            // 保存の仕方は既定（サーバー側が変わっていなければ保存する）のままにする。
            // ここを通るのは共有（CKShare）の作成だけで、CKShareの保存に
            // `.changedKeys` は使えない。
            operation.isAtomic = atomically
            operation.modifyRecordsResultBlock = { result in
                continuation.resume(with: result)
            }
            database.add(operation)
        }
    }

    private func queryAll(
        _ query: CKQuery,
        zoneID: CKRecordZone.ID,
        in database: CKDatabase
    ) async throws -> [CKRecord] {
        var allRecords: [CKRecord] = []
        var nextCursor: CKQueryOperation.Cursor?

        repeat {
            let page = try await queryPage(
                query: nextCursor == nil ? query : nil,
                cursor: nextCursor,
                zoneID: zoneID,
                in: database
            )
            allRecords.append(contentsOf: page.records)
            nextCursor = page.cursor
        } while nextCursor != nil

        return allRecords
    }

    private func queryPage(
        query: CKQuery?,
        cursor: CKQueryOperation.Cursor?,
        zoneID: CKRecordZone.ID,
        in database: CKDatabase
    ) async throws -> (records: [CKRecord], cursor: CKQueryOperation.Cursor?) {
        try await withCheckedThrowingContinuation { continuation in
            let operation: CKQueryOperation
            if let cursor {
                operation = CKQueryOperation(cursor: cursor)
            } else if let query {
                operation = CKQueryOperation(query: query)
            } else {
                continuation.resume(throwing: SyncError.missingRootRecord)
                return
            }

            let state = LockedState<(records: [CKRecord], error: Error?)>(([], nil))
            operation.zoneID = zoneID
            operation.resultsLimit = CKQueryOperation.maximumResults
            operation.recordMatchedBlock = { _, result in
                state.withLock { state in
                    switch result {
                    case let .success(record):
                        state.records.append(record)
                    case let .failure(error):
                        if state.error == nil { state.error = error }
                    }
                }
            }
            operation.queryResultBlock = { result in
                switch result {
                case let .success(cursor):
                    let page = state.withLock { $0 }
                    if let error = page.error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: (page.records, cursor))
                    }
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func accept(_ metadata: CKShare.Metadata) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            let accepted = LockedState(false)
            operation.perShareResultBlock = { _, result in
                if case .success = result {
                    accepted.withLock { $0 = true }
                }
            }
            operation.acceptSharesResultBlock = { result in
                switch result {
                case .success:
                    let didAccept = accepted.withLock { $0 }
                    if didAccept {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: SyncError.shareNotAccepted)
                    }
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
    }
}
