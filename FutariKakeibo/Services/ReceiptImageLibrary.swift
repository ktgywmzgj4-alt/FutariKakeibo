import Foundation

/// レシート画像の出し入れを1か所にまとめたもの。
///
/// 見る側から見た順番は「メモリ → 端末のファイル → iCloud」。
/// 一覧はメモリとファイルまでしか見に行かない（`thumbnail(for:)`）。
/// iCloudへ取りに行くのは、詳細画面を開いたときだけ（`display(for:...)`）。
actor ReceiptImageLibrary {
    enum LoadError: LocalizedError {
        case notStored
        case notShared

        var errorDescription: String? {
            switch self {
            case .notStored: "レシート画像を読み込めませんでした。"
            case .notShared: "レシート画像はこのiPhoneに見つかりませんでした。"
            }
        }
    }

    private let store: ReceiptImageStore
    private let cloudService: CloudKitSyncService
    /// 開いたばかりの本画像。数枚だけ持つ。足りなくなればOSが勝手に捨てる。
    private let displayCache = NSCache<NSUUID, NSData>()
    /// 一覧で使う小さな画像。数は多いが1枚10KB程度。
    private let thumbnailCache = NSCache<NSUUID, NSData>()

    init(store: ReceiptImageStore = ReceiptImageStore(), cloudService: CloudKitSyncService) {
        self.store = store
        self.cloudService = cloudService
        displayCache.countLimit = 8
        displayCache.totalCostLimit = 24 * 1024 * 1024
        thumbnailCache.countLimit = 300
        thumbnailCache.totalCostLimit = 6 * 1024 * 1024
    }

    // MARK: - 保存

    /// 撮って圧縮した1枚を端末に置く。
    func attach(_ image: ReceiptImageData, id: UUID) async throws {
        try await store.save(image, id: id)
        cache(image.display, in: displayCache, for: id)
        cache(image.thumbnail, in: thumbnailCache, for: id)
    }

    /// 端末内の1枚をiCloudへ載せる。共有していなければ何もしない。
    func upload(id: UUID, expenseID: UUID, household: Household) async throws {
        guard household.cloudLocation != nil else { return }
        guard let displayURL = await store.displayFileURLIfExists(for: id) else { return }
        let thumbnailURL = await store.thumbnailFileURLIfExists(for: id)
        try await cloudService.saveReceiptImage(
            id: id,
            expenseID: expenseID,
            displayFileURL: displayURL,
            thumbnailFileURL: thumbnailURL,
            household: household
        )
    }

    // MARK: - 読み出し

    /// 一覧用。**通信しない。** 端末にまだ無ければnilを返し、呼び出し側はアイコンを出す。
    func thumbnail(for id: UUID) async -> Data? {
        if let cached = thumbnailCache.object(forKey: id as NSUUID) {
            return cached as Data
        }
        guard let data = await store.thumbnailData(for: id) else { return nil }
        cache(data, in: thumbnailCache, for: id)
        return data
    }

    /// 詳細用。端末に無ければiCloudから取り、次からのために端末へ置く。
    func display(for id: UUID, expenseID: UUID, household: Household?) async throws -> Data {
        if let cached = displayCache.object(forKey: id as NSUUID) {
            return cached as Data
        }
        if let data = await store.displayData(for: id) {
            cache(data, in: displayCache, for: id)
            return data
        }
        guard let household, household.cloudLocation != nil else {
            throw LoadError.notShared
        }

        let fetched = try await cloudService.fetchReceiptImage(
            id: id,
            expenseID: expenseID,
            household: household
        )
        // 取り直しを繰り返さないよう、端末にも置いておく。
        // 置けなくても表示はできるので、失敗しても止めない。
        try? await store.saveDisplayData(fetched.display, id: id)
        if let thumbnail = fetched.thumbnail {
            try? await store.saveThumbnailData(thumbnail, id: id)
            cache(thumbnail, in: thumbnailCache, for: id)
        }
        cache(fetched.display, in: displayCache, for: id)
        return fetched.display
    }

    // MARK: - 片付け

    /// 1枚を端末とiCloudの両方から消す。
    ///
    /// 画像のIDは撮ったときに1枚ずつ作られ、支出1件からしか参照されない。
    /// だから、ここで消しても相手が見ている別の画像には当たらない。
    func remove(id: UUID, expenseID: UUID, household: Household?) async {
        await store.remove(id: id)
        displayCache.removeObject(forKey: id as NSUUID)
        thumbnailCache.removeObject(forKey: id as NSUUID)

        guard let household, household.cloudLocation != nil else { return }
        // 消せなくても支出の削除は済んでいる。次の起動で拾い直す。
        try? await cloudService.deleteReceiptImage(
            id: id,
            expenseID: expenseID,
            household: household
        )
    }

    func removeAll() async {
        await store.removeAll()
        displayCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
    }

    /// どの支出からも参照されていない画像と、増えすぎた分を片付ける。
    func tidy(keeping ids: Set<UUID>, protecting pending: Set<UUID>) async {
        await store.pruneOrphans(keeping: ids)
        await store.enforceLimit(protecting: pending)
    }

    func totalBytes() async -> Int {
        await store.totalBytes()
    }

    // MARK: - Private

    private func cache(_ data: Data, in cache: NSCache<NSUUID, NSData>, for id: UUID) {
        cache.setObject(data as NSData, forKey: id as NSUUID, cost: data.count)
    }
}
