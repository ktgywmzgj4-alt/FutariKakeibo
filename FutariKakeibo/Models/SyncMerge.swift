import Foundation

/// 突き合わせに使う、支出と収入に共通する項目。
protocol SyncedEntry {
    var id: UUID { get }
    var date: Date { get }
    var updatedAt: Date { get }
}

extension Expense: SyncedEntry {}
extension Income: SyncedEntry {}

/// 手元とiCloudの記録を突き合わせる（`AppStore.refreshFromCloudIfConfigured` の中身）。
///
/// - 削除印（tombstone）は両方を合わせ、同じものは新しい時刻を残す
/// - **削除印のあるものは、手元とiCloudのどちらにあっても残さない。** 時刻も見ない。
///   古い端末がオフラインのあいだに直した記録が、相手が消したあとに戻ってこないように
/// - 両方にあるものは、更新時刻の新しいほう（同じなら手元）
/// - 送り直しが要るのは、iCloudに無いか、iCloudのほうが古いものだけ
/// - 削除印のうちiCloudにまだ無いものは、送り直す
///
/// 画面やCloudKitに触らない形にしてあるので、場面ごとにテストで確かめられる（`SyncMergeTests`）。
enum SyncMerge {
    struct Result<Entry: SyncedEntry> {
        /// 突き合わせたあとの記録。日付の新しい順。
        var entries: [Entry]
        /// 両方の削除印を合わせたもの。
        var deletions: [UUID: Date]
        /// iCloudへ送り直す記録のID。
        var staleIDs: Set<UUID>
        /// iCloudへ送り直す削除印。
        var unsentDeletions: [UUID: Date]
    }

    static func merge<Entry: SyncedEntry>(
        local: [Entry],
        localDeletions: [UUID: Date],
        remote: [Entry],
        remoteDeletions: [UUID: Date]
    ) -> Result<Entry> {
        let deletions = localDeletions.merging(remoteDeletions) { max($0, $1) }
        let deleted = Set(deletions.keys)
        // 同じIDが2つあっても止まらない。`Dictionary(uniqueKeysWithValues:)` はIDが重なると
        // アプリごと落ちる。同期は30秒ごとに回るので、落ちると開くたびに落ち続ける。
        let localByID = Dictionary(local.map { ($0.id, $0) }) { newer($0, $1) }
        let remoteByID = Dictionary(remote.map { ($0.id, $0) }) { newer($0, $1) }
        let ids = Set(localByID.keys).union(remoteByID.keys).subtracting(deleted)
        let entries = ids.compactMap { id -> Entry? in
            switch (localByID[id], remoteByID[id]) {
            case let (local?, remote?): local.updatedAt >= remote.updatedAt ? local : remote
            case let (local?, nil): local
            case let (nil, remote?): remote
            case (nil, nil): nil
            }
        }.sorted { $0.date > $1.date }

        let staleIDs = staleIDs(
            local: entries.map { ($0.id, $0.updatedAt) },
            remote: remote.map { ($0.id, $0.updatedAt) }
        )
        let unsentDeletions = deletions.filter { remoteDeletions[$0.key] == nil }
        return Result(entries: entries, deletions: deletions, staleIDs: staleIDs, unsentDeletions: unsentDeletions)
    }

    /// 送り直しが要るものの印。**iCloudに無いか、iCloudのほうが古いものだけ。**
    ///
    /// ここを「全部」にすると、同期のたびに件数ぶんの往復が走り、相手の記録が
    /// 画面に出るまで何秒もかかる。実機で10秒を超えていたのがそれだった。
    /// 同じ時刻のものは送らない — 送っても中身が変わらないため。
    static func staleIDs(
        local: [(id: UUID, updatedAt: Date)],
        remote: [(id: UUID, updatedAt: Date)]
    ) -> Set<UUID> {
        let remoteByID = Dictionary(remote.map { ($0.id, $0.updatedAt) }) { max($0, $1) }
        return Set(
            local
                .filter { item in
                    guard let remoteDate = remoteByID[item.id] else { return true }
                    return item.updatedAt > remoteDate
                }
                .map(\.id)
        )
    }

    private static func newer<Entry: SyncedEntry>(_ first: Entry, _ second: Entry) -> Entry {
        second.updatedAt > first.updatedAt ? second : first
    }
}
