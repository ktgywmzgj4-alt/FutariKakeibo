import SwiftUI

/// 待っているあいだ、お財布が回る。
///
/// `ProgressView` のくるくるの代わり。既製の輪が回るより、**アプリの顔が回るほうが
/// 「これが動いている」と分かる**、という利用者の判断（2026-10-08）。
///
/// **正面を向いたまま、右へ回す。** 以前は縦軸で回していた（硬貨が回るような動き）。
/// 横を向く瞬間に財布が薄くなって絵が消えるので、
/// **正面のまま右回転にしてほしい**という利用者の指示（2026-10-13）。
/// どちらにするかは見た目の好みの話なので、指示のほうを採る。
///
/// 進み具合が分かる場面（予算の使用率など）には使わないこと。
/// そこは `ProgressView(value:)` の棒のままにする。これは「終わりが見えない待ち」用。
struct WalletSpinner: View {
    var size: CGFloat = 28
    /// 画面を読み上げたときに何を待っているか伝える。
    var label: String = "読み込み中"

    @State private var spinning = false

    var body: some View {
        Image("BrandMark")
            .resizable()
            // **原寸の色のまま出す。** 青い保存ボタンの上に置くと、
            // 指定しだいで財布が白一色に塗りつぶされてただの四角になる。
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            // 角度は正。SwiftUI では正の角度が右回り（時計回り）。
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(
                .linear(duration: 1.1).repeatForever(autoreverses: false),
                value: spinning
            )
            // 画面から外れたら止める。戻ってきたときに回り直させるためでもある。
            .onAppear { spinning = true }
            .onDisappear { spinning = false }
            .accessibilityLabel(label)
    }
}
