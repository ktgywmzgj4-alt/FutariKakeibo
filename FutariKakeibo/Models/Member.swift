import Foundation

struct Member: Identifiable, Codable, Hashable, Sendable {
    enum Role: String, Codable, Sendable {
        case owner
        case partner
    }

    let id: UUID
    var displayName: String
    var role: Role

    init(id: UUID = UUID(), displayName: String, role: Role) {
        self.id = id
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.role = role
    }
}
