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
            }
        }
    }

    struct CloudSnapshot: Sendable {
        var household: Household
        var expenses: [Expense]
        var deletedExpenseIDs: [UUID: Date]
    }

    nonisolated let container: CKContainer

    init(container: CKContainer = .default()) {
        self.container = container
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

    func prepareShare(household: Household, expenses: [Expense]) async throws -> (CloudLocation, CKShare) {
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

        if let shareReference = rootRecord.share {
            let existingRecord = try await fetchRecord(shareReference.recordID, from: database)
            if let existingShare = existingRecord as? CKShare {
                return (location, existingShare)
            }
        }

        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = "ふたり家計簿" as CKRecordValue
        share.publicPermission = .none
        try await modifyRecords(saving: [rootRecord, share], deleting: [], in: database, atomically: true)
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
        return CloudSnapshot(
            household: household,
            expenses: expenses,
            deletedExpenseIDs: deletedExpenseIDs
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
        record.parent = CKRecord.Reference(recordID: rootID, action: .deleteSelf)
        record["id"] = id.uuidString as CKRecordValue
        record["isDeleted"] = NSNumber(value: true) as CKRecordValue
        record["updatedAt"] = deletedAt as CKRecordValue
        _ = try await saveRecord(record, to: database)
    }

    // MARK: - Record mapping

    private enum RecordType {
        static let household = "Household"
        static let expense = "Expense"
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
        record.parent = CKRecord.Reference(recordID: householdRecordID, action: .deleteSelf)
        record["id"] = expense.id.uuidString as CKRecordValue
        record["isDeleted"] = NSNumber(value: false) as CKRecordValue
        record["title"] = expense.title as CKRecordValue
        record["amount"] = Int64(expense.amount) as CKRecordValue
        record["date"] = expense.date as CKRecordValue
        record["category"] = expense.category.rawValue as CKRecordValue
        record["paidByMemberID"] = expense.paidByMemberID.uuidString as CKRecordValue
        record["splitMethod"] = expense.splitMethod.rawValue as CKRecordValue
        record["note"] = expense.note as CKRecordValue
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
        return Household(
            id: id,
            name: name,
            monthlyBudget: budgetNumber.intValue,
            members: members,
            ownerMemberID: ownerID,
            categoryBudgets: categoryBudgets,
            recurringExpenses: recurringExpenses,
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
            recurringID: (record["recurringID"] as? String).flatMap(UUID.init(uuidString:)),
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
            operation.savePolicy = .changedKeys
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
