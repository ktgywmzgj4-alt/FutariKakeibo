import Foundation

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case groceries
    case dining
    case household
    case transportation
    case utilities
    case entertainment
    case health
    case beauty
    case travel
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groceries: "食費"
        case .dining: "外食"
        case .household: "日用品"
        case .transportation: "交通"
        case .utilities: "水道・光熱"
        case .entertainment: "娯楽"
        case .health: "医療・健康"
        case .beauty: "美容・衣服"
        case .travel: "旅行"
        case .other: "その他"
        }
    }

    var systemImage: String {
        switch self {
        case .groceries: "cart.fill"
        case .dining: "fork.knife"
        case .household: "house.fill"
        case .transportation: "tram.fill"
        case .utilities: "bolt.fill"
        case .entertainment: "sparkles.tv.fill"
        case .health: "cross.case.fill"
        case .beauty: "tshirt.fill"
        case .travel: "suitcase.rolling.fill"
        case .other: "ellipsis.circle.fill"
        }
    }
}
