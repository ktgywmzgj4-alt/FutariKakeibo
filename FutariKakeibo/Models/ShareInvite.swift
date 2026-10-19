import Foundation

/// 相手に伝えるための合言葉。家計のデータそのものではなく、
/// 「どの共有に入るか」を一度だけ引くための短い鍵。
struct ShareInvite: Equatable, Sendable {
    /// 見間違えやすい 0 O 1 I L は入れない。口頭でも伝えられるようにする。
    static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    static let codeLength = 8
    /// 使われないまま残った合言葉が効き続けないよう、1日で切れる。
    static let lifetime: TimeInterval = 60 * 60 * 24

    var code: String
    var shareURL: URL
    var expiresAt: Date

    var isExpired: Bool { expiresAt <= .now }

    /// 表示用に4文字ずつ区切る。
    var formattedCode: String { Self.formatted(code) }

    /// 残り時間の目安。
    var remainingDescription: String {
        let seconds = max(expiresAt.timeIntervalSinceNow, 0)
        let hours = Int(seconds / 3600)
        if hours >= 1 { return "あと約\(hours)時間で使えなくなります" }
        let minutes = max(Int(seconds / 60), 1)
        return "あと約\(minutes)分で使えなくなります"
    }

    static func formatted(_ code: String) -> String {
        let cleaned = normalized(code)
        guard cleaned.count == codeLength else { return cleaned }
        let middle = cleaned.index(cleaned.startIndex, offsetBy: 4)
        return "\(cleaned[..<middle])-\(cleaned[middle...])"
    }

    /// 入力された合言葉を照合できる形に揃える。
    /// 区切り記号、空白、大文字小文字の違いを吸収する。
    static func normalized(_ input: String) -> String {
        String(input.uppercased().filter { alphabet.contains($0) })
    }

    static func isComplete(_ input: String) -> Bool {
        normalized(input).count == codeLength
    }

    static func makeCode() -> String {
        String((0..<codeLength).compactMap { _ in alphabet.randomElement() })
    }

    /// 公開データベースに置いた合言葉の様子。
    enum State: Equatable, Sendable {
        /// 使える。
        case active
        /// もう誰かが使った（「使われた印」がある）。期限より先に見る。
        case used
        /// 期限が切れた。
        case expired
        /// 見つからない（消した、または打ち間違い）。
        case gone
    }

    /// 合言葉のレコードと「使われた印」から、いまの様子を決める。
    ///
    /// **使われた印があれば、期限の内でも使えない。** 合言葉は1回だけ。
    static func state(exists: Bool, expiresAt: Date?, isUsed: Bool, now: Date = .now) -> State {
        if isUsed { return .used }
        guard exists else { return .gone }
        guard let expiresAt, expiresAt > now else { return .expired }
        return .active
    }
}

/// この端末が発行した合言葉の控え。
///
/// 合言葉のレコード（共有のURLが入っている）は、発行した本人にしか消せない。
/// 使われた・期限が切れた・発行し直した合言葉を後で消すために、何を発行したかを端末に残す。
/// 合言葉そのもの以外（共有のURLなど）は持たない。
struct IssuedInvite: Codable, Hashable, Sendable {
    var code: String
    var expiresAt: Date
}

extension IssuedInvite {
    /// 後片付け（`AppStore.tidyIssuedInvites`）でどうするか。
    enum Disposition: Equatable, Sendable {
        /// まだ使える。残す。
        case keep
        /// 公開データベースから消して、控えからも外す。
        case withdraw
        /// もう公開データベースに無い。控えから外すだけ。
        case forget
    }

    /// いちばん新しく発行した合言葉。画面に出しているのはこれだけ。
    static func latest(in invites: [IssuedInvite]) -> IssuedInvite? {
        invites.max { $0.expiresAt < $1.expiresAt }
    }

    /// 公開データベースの様子を見に行く必要があるか。
    ///
    /// 見に行くのは、いちばん新しく、まだ期限の内の合言葉だけ。発行し直して要らなくなったものと、
    /// 期限の切れたものは、見に行かずに消してよい。
    static func needsRemoteCheck(_ invite: IssuedInvite, isLatest: Bool, now: Date = .now) -> Bool {
        isLatest && invite.expiresAt > now
    }

    /// 後片付けでどうするか。`remoteState` は見に行ったときだけ入る。
    static func disposition(
        _ invite: IssuedInvite,
        isLatest: Bool,
        remoteState: ShareInvite.State?,
        now: Date = .now
    ) -> Disposition {
        // 発行し直して要らなくなったもの、期限の切れたものは消す。
        guard isLatest, invite.expiresAt > now else { return .withdraw }
        switch remoteState {
        case .active?, nil: return .keep
        case .used?, .expired?: return .withdraw
        case .gone?: return .forget
        }
    }
}
