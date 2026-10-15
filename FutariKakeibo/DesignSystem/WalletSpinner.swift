import SwiftUI

/// 待っているあいだ、お財布が回る。
///
/// `ProgressView` のくるくるの代わり。既製の輪が回るより、**アプリの顔が回るほうが
/// 「これが動いている」と分かる**、という利用者の判断（2026-10-08）。
///
/// **回るのはお財布の絵だけ。** 以前はアプリの印（`BrandMark`）を角丸で切って回していて、
/// 絵の白い地ごと回っていた。青い保存ボタンの上では白い板が回って見えた（2026-10-15）。
/// いまは外側の白だけを抜いた `WalletGlyph` を回す（`scripts/make_wallet_glyph.py` で作る）。
/// 「¥」は白のまま残してある。
///
/// **正面を向いたまま、右へ回す**（2026-10-13 利用者の指示）。
///
/// 角度は**時刻から計算する**（`TimelineView`）。以前の「状態を切り替えて
/// `repeatForever` で回す」形は、現れた瞬間に一緒に起きている位置の変化まで
/// 同じアニメーションに巻き込むので、引っ張って更新の最中に出すと絵が流れて見えうる。
/// 時刻から角度を出せば、いつ現れても同じ速さで回るだけで、画面から消えれば止まる。
///
/// 進み具合が分かる場面（予算の使用率など）には使わないこと。
/// そこは `ProgressView(value:)` の棒のままにする。これは「終わりが見えない待ち」用。
struct WalletSpinner: View {
    var size: CGFloat = 28
    /// 画面を読み上げたときに何を待っているか伝える。
    var label: String = "読み込み中"

    /// 1回りにかかる時間。
    nonisolated static let period: TimeInterval = 1.1

    var body: some View {
        // 毎秒60コマで足りる。ProMotion の120コマまで描いても、見た目は変わらず電池だけ減る。
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            Image("WalletGlyph")
                .resizable()
                // 色をそのまま出す。テンプレート扱いになると単色で塗られ、「¥」が消える。
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: size, height: size)
                .rotationEffect(Self.angle(at: context.date))
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// その時刻の角度。0度以上360度未満で、時間とともに増える。
    /// SwiftUI では**正の角度が右回り**（時計回り）。
    nonisolated static func angle(at date: Date, period: TimeInterval = WalletSpinner.period) -> Angle {
        var phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        // 基準時刻（2001年）より前の日時だと負になる。1回り足して 0〜1 に戻す。
        if phase < 0 { phase += 1 }
        // ごく小さい負の値に1を足すと、丸めで1ちょうどになることがある。1回りは0度と同じ。
        if phase >= 1 { phase -= 1 }
        return .degrees(phase * 360)
    }
}
