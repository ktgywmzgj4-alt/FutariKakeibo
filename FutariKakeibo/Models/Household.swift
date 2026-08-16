import Foundation

struct Household: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var monthlyBudget: Int
    var members: [Member]
    var ownerMemberID: UUID
    var cloudLocation: CloudLocation?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "ふたりの家計",
        monthlyBudget: Int,
        members: [Member],
        ownerMemberID: UUID,
        cloudLocation: CloudLocation? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.monthlyBudget = max(monthlyBudget, 0)
        self.members = Array(members.prefix(2))
        self.ownerMemberID = ownerMemberID
        self.cloudLocation = cloudLocation
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var partner: Member? {
        members.first { $0.id != ownerMemberID }
    }

    func member(id: UUID) -> Member? {
        members.first { $0.id == id }
    }
}

struct CloudLocation: Codable, Hashable, Sendable {
    enum Scope: String, Codable, Sendable {
        case privateDatabase
        case sharedDatabase
    }

    var scope: Scope
    var zoneName: String
    var ownerName: String
    var rootRecordName: String
}
