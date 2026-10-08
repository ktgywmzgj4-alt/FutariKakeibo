import SwiftUI

/// 待っているあいだ、お財布が回る。
///
/// `ProgressView` のくるくるの代わり。既製の輪が回るより、**アプリの顔が回るほうが
/// 「これが動いている」と分かる**、という利用者の判断（2026-10-08）。
///
/// **平らにではなく、縦軸で回している。** 平らに回すと財布が逆さまになる瞬間があり、
/// 絵が壊れて見える。縦軸なら硬貨が回るように見えて、いつも上が上のまま。
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
            .rotation3DEffect(
                .degrees(spinning ? 360 : 0),
                axis: (x: 0, y: 1, z: 0)
            )
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
