import SwiftUI

extension ExpenseCategory {
    var color: Color {
        switch self {
        case .groceries: AppTheme.terracotta
        case .dining: Color(red: 0.91, green: 0.47, blue: 0.28)
        case .household: AppTheme.sage
        case .transportation: Color(red: 0.34, green: 0.54, blue: 0.63)
        case .utilities: AppTheme.gold
        case .entertainment: Color(red: 0.53, green: 0.40, blue: 0.67)
        case .health: Color(red: 0.78, green: 0.35, blue: 0.39)
        case .beauty: Color(red: 0.78, green: 0.48, blue: 0.60)
        case .travel: Color(red: 0.26, green: 0.48, blue: 0.40)
        case .other: AppTheme.secondaryText
        }
    }
}
