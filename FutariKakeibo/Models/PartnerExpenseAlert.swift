import Foundation

/// 相手が新しく登録した支出を、この端末で知らせるかどうかの決まり（T-045）。
///
/// - 知らせるのは **相手が新しく登録した支出だけ**。自分の登録・直し・削除は知らせない
/// - 誰が登録したかは、iCloudの記録に付く「作成者」（`CKRecord.creatorUserRecordID`）で見る。
///   支払った人（`paidByMemberID`）とは別。iCloudが自分で付ける欄なので、CloudKitの項目は増えない（T-044）
/// - 同期の前から手元にあった支出は知らせない。家計簿に入った・取り戻した・入れ直したときに
///   取り込んだ支出は、その時点で手元にあるので知らせない
/// - 定期支出の自動計上は知らせない（ふたりの端末がそれぞれ同じ支出を作るため）
/// - 登録から日のたった支出は知らせない（`freshness`）。相手の端末が長くオフラインだったときなど
/// - 1回の同期で何件届いても、通知は1つにまとめる
/// - 通知の文に金額・店名・内容は入れない（ロック画面に出るため）
///
/// 画面・通知・CloudKitに触らない形にして、場面ごとにテストで確かめる（`PartnerExpenseAlertTests`）。
enum PartnerExpenseAlert {
    /// 登録から3日を過ぎた支出は知らせない。
    static let freshness: TimeInterval = 60 * 60 * 24 * 3
    /// 知らせた支出のIDを、端末にいくつまで覚えておくか（同じ支出を2回知らせないため）。
    static let rememberedLimit = 300
    /// 通知をまとめる名前。通知センターで1か所に重なる。
    static let threadIdentifier = "partner-expenses"
    /// 通知に入れる、開く支出のID。
    static let expenseIDKey = "expenseID"

    /// この端末の利用者を見分ける手がかり。
    struct Identity: Equatable, Sendable {
        /// CloudKitが「この端末の利用者」を表すのに使う決まった名前（`CKCurrentUserDefaultName`）。
        var placeholder: String
        /// この利用者のユーザーレコードの名前。分からないあいだは nil。
        var recordName: String?
    }

    enum Registrant: Equatable, Sendable {
        case me
        case partner
        /// 分からない（作成者が無い・自分の名前がまだ分からない）
        case unknown
    }

    /// 支出を登録したのは誰か。
    ///
    /// **分からないときは相手と決めつけない。** 自分の名前が分からないまま「自分ではない」とすると、
    /// 自分で登録した支出を「パートナーが登録しました」と知らせてしまう。
    static func registrant(creator: String?, identity: Identity) -> Registrant {
        guard let creator, !creator.isEmpty else { return .unknown }
        if creator == identity.placeholder || creator == identity.recordName { return .me }
        return identity.recordName == nil ? .unknown : .partner
    }

    /// 知らせる候補（登録したのが誰かは、まだ見ていない）。作成者を調べる前のふるい。
    ///
    /// - `knownBefore`: 同期の前から手元にあった支出のID（削除印も含む）
    /// - `merged`: 同期のあとの支出（削除されたものは入っていない）
    static func candidates(
        knownBefore: Set<UUID>,
        merged: [Expense],
        alreadyAnnounced: Set<UUID>,
        now: Date
    ) -> [Expense] {
        merged.filter { expense in
            !knownBefore.contains(expense.id)
                && !alreadyAnnounced.contains(expense.id)
                && expense.recurringID == nil
                && expense.createdAt >= now.addingTimeInterval(-freshness)
        }
    }

    /// 今回の同期で知らせる支出。登録の古い順。
    static func expensesToAnnounce(
        knownBefore: Set<UUID>,
        merged: [Expense],
        creators: [UUID: String],
        identity: Identity,
        alreadyAnnounced: Set<UUID>,
        now: Date
    ) -> [Expense] {
        candidates(knownBefore: knownBefore, merged: merged, alreadyAnnounced: alreadyAnnounced, now: now)
            .filter { registrant(creator: creators[$0.id], identity: identity) == .partner }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// 通知の中身。
    struct Content: Equatable, Sendable {
        /// 同じ名前の通知は重ならずに置き換わる。
        var identifier: String
        var body: String
        /// 1件のときだけ入る。押すとその支出を開く。
        var expenseID: UUID?
    }

    /// 通知の文。**金額・店名・内容は入れない。** アプリの名前（ふたり家計簿）はiPhoneが上に出す。
    static func content(for expenses: [Expense]) -> Content? {
        guard let last = expenses.last else { return nil }
        if expenses.count == 1 {
            return Content(
                identifier: "partner-expense-\(last.id.uuidString)",
                body: "パートナーが新しい支出を登録しました",
                expenseID: last.id
            )
        }
        return Content(
            identifier: "partner-expenses-\(last.id.uuidString)",
            body: "パートナーが新しい支出を\(expenses.count)件登録しました",
            expenseID: nil
        )
    }

    /// 通知を押したときに開く支出。
    static func expenseID(from userInfo: [AnyHashable: Any]) -> UUID? {
        (userInfo[expenseIDKey] as? String).flatMap { UUID(uuidString: $0) }
    }

    /// 知らせた支出の控え。新しいものを後ろに足し、多くなったら古いものから捨てる。
    static func remembering(_ ids: [UUID], in announced: [UUID]) -> [UUID] {
        var result = announced
        for id in ids where !result.contains(id) {
            result.append(id)
        }
        return Array(result.suffix(rememberedLimit))
    }

    /// CloudKitからの合図（購読の知らせ）か。中身は使わず、同期のきっかけにだけ使う（T-047）。
    static func isCloudKitPush(_ userInfo: [AnyHashable: Any]) -> Bool {
        userInfo["ck"] != nil
    }
}
