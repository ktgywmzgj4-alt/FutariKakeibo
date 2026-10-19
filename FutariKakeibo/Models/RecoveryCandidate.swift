import Foundation

/// iCloudから取り戻せる家計簿の1つ。選ぶ画面に出す要約だけを持つ。
///
/// アプリを入れ直したとき、iCloudに家計簿が2つ以上あることがある。参加する前に一度でも
/// 合言葉を発行した人は、自分で作った家計簿（プライベート側）と、相手から共有された家計簿
/// （共有側）の両方を持っている。どちらに戻るかは利用者に選んでもらう（2026-10-19 監査）。
struct RecoveryCandidate: Identifiable, Equatable, Sendable {
    var location: CloudLocation
    var householdName: String
    var memberNames: [String]
    var expenseCount: Int
    var incomeCount: Int
    /// いちばん最近の記録（家計簿の設定・支出・収入の更新時刻のうち最も新しいもの）。
    var lastActivity: Date

    var id: String { Self.key(for: location) }
    /// 自分で作った家計簿か（プライベート側）。相手から共有された家計簿なら false。
    var isOwnHousehold: Bool { location.scope == .privateDatabase }

    init(
        location: CloudLocation,
        householdName: String,
        memberNames: [String],
        expenseCount: Int,
        incomeCount: Int,
        lastActivity: Date
    ) {
        self.location = location
        self.householdName = householdName
        self.memberNames = memberNames
        self.expenseCount = expenseCount
        self.incomeCount = incomeCount
        self.lastActivity = lastActivity
    }

    init(location: CloudLocation, household: Household, expenses: [Expense], incomes: [Income]) {
        let latest = ([household.updatedAt] + expenses.map(\.updatedAt) + incomes.map(\.updatedAt)).max()
            ?? household.updatedAt
        self.init(
            location: location,
            householdName: household.name,
            memberNames: household.members.map(\.displayName),
            expenseCount: expenses.count,
            incomeCount: incomes.count,
            lastActivity: latest
        )
    }

    /// 場所ごとに1つに決まる名前。取ってきた中身を覚えておくときの鍵にも使う。
    static func key(for location: CloudLocation) -> String {
        "\(location.scope.rawValue)/\(location.ownerName)/\(location.zoneName)"
    }

    /// 選ぶ画面の並び。**いちばん最近まで使われていたものを先頭に**する。
    ///
    /// ふだん使っている家計簿は毎日のように記録が増える。参加する前に作って放ってある家計簿は
    /// 古いまま。どちらが「いつもの家計簿」かの手がかりになる。
    /// 同じ時刻なら、相手から共有された家計簿（ふたりで使っているほう）を先にする。
    static func ranked(_ candidates: [RecoveryCandidate]) -> [RecoveryCandidate] {
        candidates.sorted { lhs, rhs in
            if lhs.lastActivity != rhs.lastActivity { return lhs.lastActivity > rhs.lastActivity }
            return !lhs.isOwnHousehold && rhs.isOwnHousehold
        }
    }
}
