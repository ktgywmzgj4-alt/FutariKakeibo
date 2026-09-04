import SwiftUI

/// 純白と黒を土台に、ブルーとコーラルを小さく差す。
///
/// 差し色は薄めず、面積を小さく保つ。カード全体を着色しない。
/// 虹色・色ずれ・文字の影・グラデーションは使わない。
enum AppTheme {
    /// 紙。純白。クリームや象牙色に寄せない。
    static let background = Color(hex: 0xFFFFFF)
    /// カード。背景と同じ純白で、細い境界線だけで区切る。
    static let card = Color(hex: 0xFFFFFF)
    /// 本文と金額の黒。
    static let ink = Color(hex: 0x000000)
    /// 補足の文字。
    static let secondaryText = Color(hex: 0x6B6B73)
    /// 罫線とカードの輪郭。
    static let line = Color(hex: 0xE7E7EC)
    /// 押せるもの、選ばれているもの。
    static let accent = Color(hex: 0x2D5BD1)
    /// 選ばれている小さな面の背景。ここだけ淡く敷いてよい。
    static let accentSoft = Color(hex: 0xEEF3FF)
    /// 2人目の識別色。人の見分けに使う色で、支出やエラーの色ではない。
    static let coral = Color(hex: 0xEE5D59)

    /// 良い状態。予算内、収支の黒字。
    static let positive = Color(hex: 0x179C61)
    static let positiveSoft = Color(hex: 0xEDF7F1)
    /// 注意。予算に近づいている。
    static let warning = Color(hex: 0xF29D1B)
    /// 危険。予算超過、削除。
    static let danger = Color(hex: 0xD62839)

    /// 画面の左右の余白。
    static let screenPadding: CGFloat = 20
    /// カードの中の余白。
    static let cardPadding: CGFloat = 16
    /// カードとカードの間。
    static let cardSpacing: CGFloat = 16
    static let cornerRadius: CGFloat = 18

    /// メンバーの識別色。**性別ではなく、家計に登録された順**で決まる。
    /// 同じ人が全画面で同じ色になるよう、色は必ずここから取る。
    static func memberColor(at index: Int) -> Color {
        index == 0 ? accent : coral
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Household {
    /// この人の識別色。登録順で決まるので、どの画面でも同じ色になる。
    func color(of memberID: UUID?) -> Color {
        guard let memberID, let index = members.firstIndex(where: { $0.id == memberID }) else {
            return AppTheme.accent
        }
        return AppTheme.memberColor(at: index)
    }
}

struct AppCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppTheme.cardPadding)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(AppTheme.line, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
    }
}

extension View {
    func appCard() -> some View {
        modifier(AppCardModifier())
    }
}

/// 画面の見出し。左寄せで、カードの中の文字と左端をそろえる。
/// 主役は金額なので、見出しはそれより控えめにする。
struct ScreenTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(AppTheme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// メンバーの目印。白地に本人の色の輪郭、頭文字は黒。
struct MemberAvatar: View {
    let name: String
    let color: Color
    var size: CGFloat = 30

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1))
    }

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(AppTheme.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(AppTheme.card))
            .overlay(Circle().stroke(color, lineWidth: 1.6))
            .accessibilityHidden(true)
    }
}

/// 目印と名前をひと組にしたもの。ホームの上部と、精算の行で使う。
struct MemberTag: View {
    let name: String
    let color: Color
    var avatarSize: CGFloat = 30
    var font: Font = .subheadline

    var body: some View {
        HStack(spacing: 8) {
            MemberAvatar(name: name, color: color, size: avatarSize)
            Text(name)
                .font(font)
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
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
