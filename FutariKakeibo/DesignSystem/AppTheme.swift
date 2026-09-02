import SwiftUI

/// 純白の紙に黒で刷った見た目を土台に、文字の右の輪郭から
/// 虹がわずかに覗く。色は差し色ではなく、その覗く光だけが持つ。
enum AppTheme {
    /// 紙。純白。
    static let background = Color.white
    /// カード。背景と同じ白で、境界線と影だけで持ち上げる。
    static let card = Color.white
    /// 本文の黒。真っ黒よりわずかに沈めて、白地で目が痛くならないようにする。
    static let ink = Color(red: 0.05, green: 0.05, blue: 0.06)
    /// 補足の文字。
    static let secondaryText = Color(red: 0.44, green: 0.44, blue: 0.47)
    /// 罫線とカードの輪郭。
    static let line = Color(red: 0.89, green: 0.89, blue: 0.91)
    /// 押せるもの。虹の中央にある青を単色で取り出したもの。
    static let accent = Color(red: 0.13, green: 0.44, blue: 0.94)
    static let accentSoft = Color(red: 0.87, green: 0.92, blue: 1.00)
    /// 良い状態。予算内、収支の黒字。
    static let positive = Color(red: 0.09, green: 0.63, blue: 0.40)
    static let positiveSoft = Color(red: 0.87, green: 0.96, blue: 0.91)
    /// 注意。予算に近づいている。
    static let warning = Color(red: 0.95, green: 0.62, blue: 0.11)
    /// 危険。予算超過、削除。
    static let danger = Color(red: 0.84, green: 0.15, blue: 0.24)

    /// 虹。文字の輪郭から覗かせるほか、進捗や強調にも使う。
    static let spectrumColors: [Color] = [
        Color(red: 0.93, green: 0.20, blue: 0.28),
        Color(red: 0.97, green: 0.55, blue: 0.13),
        Color(red: 0.95, green: 0.80, blue: 0.16),
        Color(red: 0.20, green: 0.72, blue: 0.44),
        Color(red: 0.13, green: 0.50, blue: 0.93),
        Color(red: 0.53, green: 0.31, blue: 0.85)
    ]

    static let spectrum = LinearGradient(
        colors: spectrumColors,
        startPoint: .leading,
        endPoint: .trailing
    )
}

struct AppCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.line, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 10, y: 3)
    }
}

/// 文字の右の輪郭から虹をわずかに覗かせる。
/// 同じ文字を虹色で少し右にずらして後ろに敷き、その分だけがはみ出す。
struct SpectrumEdgeModifier: ViewModifier {
    var offset: CGFloat = 1.5

    func body(content: Content) -> some View {
        content
            .background(alignment: .leading) {
                // content にはすでに文字色（黒）が付いているため、
                // ここで foregroundStyle を重ねても虹色にはならず、
                // 黒い文字がもう1枚ずれて並ぶだけになる（実機で二重に見えていた原因）。
                // 文字の形で虹色を切り抜いて、その分だけ右へずらす。
                AppTheme.spectrum
                    .mask(alignment: .leading) { content }
                    .offset(x: offset)
                    .accessibilityHidden(true)
            }
    }
}

extension View {
    func appCard() -> some View {
        modifier(AppCardModifier())
    }

    /// 見出しや金額など、目を引かせたい文字にだけ使う。
    func spectrumEdge(_ offset: CGFloat = 1.5) -> some View {
        modifier(SpectrumEdgeModifier(offset: offset))
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
