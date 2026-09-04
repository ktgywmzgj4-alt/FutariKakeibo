import SwiftUI

extension ExpenseCategory {
    /// グラフと内訳でカテゴリを見分けるための色。
    /// 文字は黒に統一しているので、色が付くのはアイコンとグラフの面だけ。
    var color: Color {
        switch self {
        case .groceries: Color(red: 0.93, green: 0.20, blue: 0.28)
        case .dining: Color(red: 0.97, green: 0.47, blue: 0.13)
        case .household: Color(red: 0.85, green: 0.68, blue: 0.10)
        case .transportation: Color(red: 0.20, green: 0.72, blue: 0.44)
        case .utilities: Color(red: 0.09, green: 0.66, blue: 0.66)
        case .entertainment: Color(red: 0.13, green: 0.50, blue: 0.93)
        case .health: Color(red: 0.42, green: 0.33, blue: 0.88)
        case .beauty: Color(red: 0.75, green: 0.25, blue: 0.72)
        case .travel: Color(red: 0.05, green: 0.55, blue: 0.55)
        case .other: Color(red: 0.44, green: 0.44, blue: 0.47)
        }
    }
}
