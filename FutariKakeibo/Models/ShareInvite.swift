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
}
