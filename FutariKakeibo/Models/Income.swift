import Foundation

/// 給与や臨時収入など、家計に入ってきたお金の記録。
/// 支出と違ってカテゴリや折半の考え方を持たないため、別の型として扱う。
struct Income: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var amount: Int
    var date: Date
    var source: IncomeSource
    /// 受け取った人。誰の収入かは精算ではなく振り返りのために持つ。
    var receivedByMemberID: UUID
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        amount: Int,
        date: Date = .now,
        source: IncomeSource = .salary,
        receivedByMemberID: UUID,
        note: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.amount = max(amount, 0)
        self.date = date
        self.source = source
        self.receivedByMemberID = receivedByMemberID
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isValid: Bool {
        !title.isEmpty && amount > 0
    }
}

enum IncomeSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case salary
    case bonus
    case sideJob
    case allowance
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .salary: "給与"
        case .bonus: "賞与"
        case .sideJob: "副収入"
        case .allowance: "臨時・贈与"
        case .other: "その他"
        }
    }

    var systemImage: String {
        switch self {
        case .salary: "yensign.circle.fill"
        case .bonus: "gift.fill"
        case .sideJob: "laptopcomputer"
        case .allowance: "hands.sparkles.fill"
        case .other: "ellipsis.circle.fill"
        }
    }
}
