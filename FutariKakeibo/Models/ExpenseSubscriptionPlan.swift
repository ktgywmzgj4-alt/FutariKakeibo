import Foundation

/// CloudKitの購読（相手の支出が変わったときの合図）をどうするか（T-047）。
///
/// - 通知がONで、家計簿を共有していれば、家計簿のある側（作った人はプライベート側、参加した人は共有側）に1つ置く
/// - 通知をOFFにしたら外す（アプリを裏で起こさない。同期は開いているあいだ今までどおり続く）
/// - 置いた購読は、1日のあいだは置き直さない（毎回の同期で送らない。サーバーで消えていても1日で戻る）
/// - **置く・外すのに失敗したら、1時間は送り直さない。** 失敗し続けても同期のたびに送らない
///   （電池のためと、CloudKit に回数を絞られていつもの同期まで遅くならないため。Apple の CKSubscription の説明には
///   「本番の環境で直接作るとエラーになる」とあり、データベースの購読に当てはまるかは TestFlight でしか確かめられない）
/// - **家計簿が見えないときは触らない。** 起動の途中など、手元の読み込みが済む前に外してしまわないため
///
/// 画面・CloudKitに触らない形にして、場面ごとにテストで確かめる（`ExpenseSubscriptionPlanTests`）。
enum ExpenseSubscriptionPlan {
    enum Action: Equatable, Sendable {
        case keep
        case subscribe(CloudLocation.Scope)
        case unsubscribe(CloudLocation.Scope)
        /// 家計簿の置き場所の側が変わった（自分の家計簿から、相手の家計簿に入ったなど）。古いほうを外して新しいほうに置く。
        case move(from: CloudLocation.Scope, to: CloudLocation.Scope)
    }

    /// 同じ購読を置き直す間隔。
    static let refreshInterval: TimeInterval = 60 * 60 * 24
    /// 置く・外すのに失敗したあと、もう一度試すまでの間隔。
    static let retryInterval: TimeInterval = 60 * 60

    static func action(
        notificationsOn: Bool,
        location: CloudLocation?,
        subscribedScope: CloudLocation.Scope?,
        subscribedAt: Date?,
        failedAt: Date?,
        now: Date
    ) -> Action {
        let action = plannedAction(
            notificationsOn: notificationsOn,
            location: location,
            subscribedScope: subscribedScope,
            subscribedAt: subscribedAt,
            now: now
        )
        // 時刻が未来（端末の時計がずれた）の失敗では待たない。
        if action != .keep,
           let failedAt,
           failedAt <= now,
           now.timeIntervalSince(failedAt) < retryInterval {
            return .keep
        }
        return action
    }

    private static func plannedAction(
        notificationsOn: Bool,
        location: CloudLocation?,
        subscribedScope: CloudLocation.Scope?,
        subscribedAt: Date?,
        now: Date
    ) -> Action {
        guard notificationsOn else {
            return subscribedScope.map { .unsubscribe($0) } ?? .keep
        }
        guard let scope = location?.scope else { return .keep }
        if let subscribedScope, subscribedScope != scope {
            return .move(from: subscribedScope, to: scope)
        }
        if subscribedScope == scope,
           let subscribedAt,
           subscribedAt <= now,
           now.timeIntervalSince(subscribedAt) < refreshInterval {
            return .keep
        }
        return .subscribe(scope)
    }
}
