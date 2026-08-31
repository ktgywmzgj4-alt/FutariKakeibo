import Foundation

actor LocalSnapshotStore {
    enum StoreError: LocalizedError {
        case unsupportedSchema(Int)

        var errorDescription: String? {
            switch self {
            case let .unsupportedSchema(version):
                "保存データの形式（v\(version)）は、このバージョンのアプリでは開けません。"
            }
        }
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directoryURL: URL? = nil) {
        let resolvedDirectory = directoryURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        // アプリの保存先が取得できない極端な状況でも起動時にクラッシュしないよう、
        // 一時ディレクトリへ安全にフォールバックする。
        let baseDirectory = resolvedDirectory ?? FileManager.default.temporaryDirectory
        let appDirectory = baseDirectory.appendingPathComponent("FutariKakeibo", isDirectory: true)
        fileURL = appDirectory.appendingPathComponent("snapshot.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    func load() throws -> AppSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppSnapshot()
        }
        let data = try Data(contentsOf: fileURL)
        let snapshot = try decoder.decode(AppSnapshot.self, from: data)
        guard snapshot.schemaVersion <= AppSnapshot.currentSchemaVersion else {
            throw StoreError.unsupportedSchema(snapshot.schemaVersion)
        }
        return snapshot
    }

    func save(_ snapshot: AppSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )

        // 読み込んだ時点の版に関わらず、書き出すファイルは常に現在の形式にそろえる。
        var upgraded = snapshot
        upgraded.schemaVersion = AppSnapshot.currentSchemaVersion
        let data = try encoder.encode(upgraded)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func deleteAll() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
