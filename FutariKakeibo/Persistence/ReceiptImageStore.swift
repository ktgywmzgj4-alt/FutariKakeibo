import Foundation

/// レシート画像を、家計簿データとは別のファイルとして持つ。
///
/// `snapshot.json` に画像を入れると、支出を1件足すたびに画像すべてを
/// 書き直すことになる。1枚1ファイルに分けておけば、必要な1枚だけを読める。
///
/// - 本画像 `<ID>.jpg` … 詳細画面で見る用（長辺1600px）
/// - 縮小画像 `<ID>-thumb.jpg` … 一覧で見る用（長辺240px）
actor ReceiptImageStore {
    /// 端末に置いておく画像の合計の上限。
    /// これを超えたら、**iCloudから取り直せるものだけ**を古い順に消す。
    static let defaultMaxBytes = 150 * 1024 * 1024

    private let directory: URL
    private var didPrepareDirectory = false

    init(directoryURL: URL? = nil) {
        let resolvedDirectory = directoryURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        // 保存先が取れない極端な状況でも起動時に落とさない。
        let baseDirectory = resolvedDirectory ?? FileManager.default.temporaryDirectory
        directory = baseDirectory
            .appendingPathComponent("FutariKakeibo", isDirectory: true)
            .appendingPathComponent("Receipts", isDirectory: true)
    }

    // MARK: - 保存

    func save(_ image: ReceiptImageData, id: UUID) throws {
        try prepareDirectoryIfNeeded()
        try write(image.display, to: displayURL(for: id))
        try write(image.thumbnail, to: thumbnailURL(for: id))
    }

    /// iCloudから取ってきた本画像を置く。
    func saveDisplayData(_ data: Data, id: UUID) throws {
        try prepareDirectoryIfNeeded()
        try write(data, to: displayURL(for: id))
    }

    /// iCloudから取ってきた縮小画像を置く。
    func saveThumbnailData(_ data: Data, id: UUID) throws {
        try prepareDirectoryIfNeeded()
        try write(data, to: thumbnailURL(for: id))
    }

    // MARK: - 読み出し

    func displayData(for id: UUID) -> Data? {
        try? Data(contentsOf: displayURL(for: id))
    }

    func thumbnailData(for id: UUID) -> Data? {
        try? Data(contentsOf: thumbnailURL(for: id))
    }

    func hasDisplayImage(for id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: displayURL(for: id).path)
    }

    /// CloudKitへ載せるときのファイルの場所。無ければnil。
    func displayFileURLIfExists(for id: UUID) -> URL? {
        let url = displayURL(for: id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func thumbnailFileURLIfExists(for id: UUID) -> URL? {
        let url = thumbnailURL(for: id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - 片付け

    func remove(id: UUID) {
        try? FileManager.default.removeItem(at: displayURL(for: id))
        try? FileManager.default.removeItem(at: thumbnailURL(for: id))
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        didPrepareDirectory = false
    }

    /// どの支出からも参照されていない画像を消す。
    ///
    /// 支出を消した直後にアプリが終わると、ファイルだけが残ることがある。
    /// 起動のたびにここで拾う。戻り値は消した枚数。
    @discardableResult
    func pruneOrphans(keeping ids: Set<UUID>) -> Int {
        var removed = 0
        for id in storedIDs() where !ids.contains(id) {
            remove(id: id)
            removed += 1
        }
        return removed
    }

    /// 上限を超えた分の**本画像だけ**を古い順に消す。縮小画像は小さいので残す。
    ///
    /// `protecting` はまだiCloudへ送れていない画像。端末内が唯一の原本なので消さない。
    /// 共有していないときは全部がここに入るため、勝手に減ることはない。
    @discardableResult
    func enforceLimit(maxBytes: Int = ReceiptImageStore.defaultMaxBytes, protecting: Set<UUID> = []) -> Int {
        var total = totalBytes()
        guard total > maxBytes else { return 0 }

        let candidates = storedIDs()
            .filter { !protecting.contains($0) }
            .compactMap { id -> (id: UUID, url: URL, size: Int, date: Date)? in
                let url = displayURL(for: id)
                guard let values = try? url.resourceValues(
                    forKeys: [.fileSizeKey, .contentModificationDateKey]
                ) else { return nil }
                return (id, url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.date < $1.date }

        var removed = 0
        for candidate in candidates {
            guard total > maxBytes else { break }
            try? FileManager.default.removeItem(at: candidate.url)
            total -= candidate.size
            removed += 1
        }
        return removed
    }

    func totalBytes() -> Int {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return contents.reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }

    /// 端末内にある画像のID。ファイル名から拾う。
    func storedIDs() -> Set<UUID> {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        var ids: Set<UUID> = []
        for url in contents where url.pathExtension == "jpg" {
            var name = url.deletingPathExtension().lastPathComponent
            if name.hasSuffix(thumbnailSuffix) {
                name = String(name.dropLast(thumbnailSuffix.count))
            }
            if let id = UUID(uuidString: name) { ids.insert(id) }
        }
        return ids
    }

    // MARK: - Private

    private let thumbnailSuffix = "-thumb"

    private func displayURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).jpg")
    }

    private func thumbnailURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString)\(thumbnailSuffix).jpg")
    }

    private func prepareDirectoryIfNeeded() throws {
        guard !didPrepareDirectory else { return }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        didPrepareDirectory = true
    }

    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
