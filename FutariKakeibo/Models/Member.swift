import Foundation

struct Member: Identifiable, Codable, Hashable, Sendable {
    enum Role: String, Codable, Sendable {
        case owner
        case partner
    }

    let id: UUID
    var displayName: String
    var role: Role
    // 既存のメンバーJSONに追加する。旧データではnilのまま読み込める。
    // 未知のIDも文字列のまま残し、将来の色を名前の編集で消さない。
    private var colorID: String?

    var color: MemberColor {
        get {
            colorID.flatMap(MemberColor.init(rawValue:))
                ?? (role == .owner ? .blue : .coral)
        }
        set { colorID = newValue.rawValue }
    }

    init(id: UUID = UUID(), displayName: String, role: Role, color: MemberColor? = nil) {
        self.id = id
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.role = role
        self.colorID = color?.rawValue
    }
}

/// 保存するのは色のIDだけ。表示名やSwiftUIのColorは保存しない。
enum MemberColor: String, CaseIterable, Sendable {
    case blue, coral, teal, purple, orange, pink

    var displayName: String {
        switch self {
        case .blue: "ブルー"
        case .coral: "コーラル"
        case .teal: "ティール"
        case .purple: "パープル"
        case .orange: "オレンジ"
        case .pink: "ピンク"
        }
    }
}
