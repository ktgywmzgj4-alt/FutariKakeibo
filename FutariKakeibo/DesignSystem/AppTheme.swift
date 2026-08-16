import SwiftUI

enum AppTheme {
    static let background = Color(red: 1.00, green: 0.97, blue: 0.91)
    static let card = Color(red: 1.00, green: 0.99, blue: 0.96)
    static let terracotta = Color(red: 0.84, green: 0.31, blue: 0.16)
    static let terracottaSoft = Color(red: 0.95, green: 0.76, blue: 0.65)
    static let sage = Color(red: 0.48, green: 0.61, blue: 0.47)
    static let sageSoft = Color(red: 0.83, green: 0.88, blue: 0.79)
    static let deepGreen = Color(red: 0.13, green: 0.23, blue: 0.20)
    static let gold = Color(red: 0.89, green: 0.69, blue: 0.38)
    static let secondaryText = Color(red: 0.39, green: 0.38, blue: 0.33)
    static let danger = Color(red: 0.72, green: 0.18, blue: 0.16)
}

struct AppCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: AppTheme.deepGreen.opacity(0.07), radius: 14, y: 6)
    }
}

extension View {
    func appCard() -> some View {
        modifier(AppCardModifier())
    }
}

extension Int {
    var yenText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "JPY"
        formatter.currencySymbol = "¥"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: self)) ?? "¥\(self)"
    }
}
