import Foundation

/// 共有を「参加者を名指しする形」に移す前に、この端末で確かめること（T-048）。
///
/// **まだ画面からは使わない。** 移すこと自体は、利用者の承認を得てから入れる
/// （`Docs/SHARING_MIGRATION_PLAN.md`）。移すときに、手元にしか無い記録を置き去りにしない
/// 入口の条件を先に決めて、テストで押さえておく。
///
/// ここで見るのは、この端末で分かることだけ。パートナーの端末の同期が済んでいるかは、
/// 移す画面でパートナーに確かめてもらう（計画の5章）。
enum ShareMigrationReadiness {
    enum Blocker: Equatable, Sendable {
        /// 共有していない（移すものが無い）。
        case notShared
        /// 家計簿を作った人の端末ではない。共有の形を変えられるのは作った人だけ。
        case notOwner
        /// 直前の同期が済んでいない。iCloudへ送れていない記録が残っているかもしれない。
        case notRecentlySynced
        /// iCloudへ送れていないレシート画像がある。
        case pendingReceiptImages(Int)
    }

    /// 同期が「直前」と言える長さ。移す前にもう一度同期してもらう。
    static let recentSyncWindow: TimeInterval = 5 * 60

    /// 移すのを止める理由。空なら、この端末については移してよい。
    static func blockers(
        location: CloudLocation?,
        lastSyncedAt: Date?,
        pendingReceiptImageCount: Int,
        now: Date
    ) -> [Blocker] {
        guard let location else { return [.notShared] }
        var blockers: [Blocker] = []
        if location.scope != .privateDatabase {
            blockers.append(.notOwner)
        }
        let synced = lastSyncedAt.map { $0 <= now && now.timeIntervalSince($0) <= recentSyncWindow } ?? false
        if !synced {
            blockers.append(.notRecentlySynced)
        }
        if pendingReceiptImageCount > 0 {
            blockers.append(.pendingReceiptImages(pendingReceiptImageCount))
        }
        return blockers
    }
}
