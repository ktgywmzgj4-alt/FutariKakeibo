import SwiftUI
import UIKit

/// レシートを大きく見る画面。指を広げると拡大でき、2回叩くとその場所へ寄る。
///
/// 画像は詳細を開いたこのときにだけ読む。端末に無ければiCloudから取ってくるので、
/// 「読み込み中」と「読み込めなかった」の両方を必ず画面に出す。落とさない。
struct ReceiptImageViewer: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let expense: Expense

    private enum Phase {
        case loading
        case ready(UIImage)
        case failed(String)
    }

    @State private var phase: Phase = .loading

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    loadingView
                case let .ready(image):
                    ZoomableImage(image: image)
                        .accessibilityLabel("レシートの画像")
                        .accessibilityHint("指を広げると拡大、2回叩くとその場所へ寄ります")
                case let .failed(message):
                    failureView(message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background)
            .navigationTitle("レシート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            WalletSpinner(size: 44, label: "レシートを読み込み中")
            Text("レシートを読み込み中…")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(AppTheme.warning)
            Text("レシート画像を読み込めませんでした")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text(message)
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
            Button("もう一度試す") {
                Task { await load() }
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.accent)
        }
        .padding(AppTheme.screenPadding)
    }

    private func load() async {
        phase = .loading
        do {
            let data = try await store.receiptImage(for: expense)
            guard let image = UIImage(data: data) else {
                phase = .failed("画像の形式を読み取れませんでした。")
                return
            }
            phase = .ready(image)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

/// 写真アプリと同じ操作感で拡大する。
///
/// **SwiftUIのジェスチャで自前に作ると、どうしてももたつく。**
/// 指の動きが毎回SwiftUIの状態更新を通るうえ、慣性も端の跳ね返りも無い。
/// `UIScrollView` はそれを全部持っていて、拡大と移動を画面側で処理する。
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ReceiptScrollView {
        ReceiptScrollView(image: image)
    }

    func updateUIView(_ scrollView: ReceiptScrollView, context: Context) {
        scrollView.show(image)
    }
}

/// レシート1枚を、全体が入った状態で見せ、そこから拡大できるようにする。
///
/// **大きさを合わせるのは `layoutSubviews` の仕事にしてある。** 以前は
/// `UIViewRepresentable.updateUIView` から合わせていて、画像が開いた瞬間に
/// 拡大されきった状態で出るうえ、指一本で動かせなかった。
/// SwiftUIは**スクロールビューの大きさが決まったときに `updateUIView` を呼ばない**。
/// 初回は `bounds` が 0 のまま呼ばれるので、`UIImageView(image:)` が付けた
/// 画像の実寸（写真なら3000点超）のframeがそのまま残り、`contentSize` も
/// 入らなかった。だから巨大な画像の左上だけが見え、スクロールビューは
/// 「動かす先が無い」と思っていた。ピンチすると `UIScrollView` が
/// `contentSize` を計算し直すので、そこから動くようになっていた。
/// 症状は2つだが原因は1つ。
///
/// **`updateUIView` で大きさを合わせる形に戻さないでください。**
private final class ReceiptScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    /// 倍率を組み直した時点の画面の大きさ。回転したときだけやり直す。
    private var sizeWhenScalesWereSet: CGSize = .zero

    init(image: UIImage) {
        super.init(frame: .zero)

        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        backgroundColor = .clear
        contentInsetAdjustmentBehavior = .never
        delegate = self

        // 画像は等倍で置く。縮めるのは倍率（zoomScale）の側でやる。
        // こうしておくと、動かせる範囲が画像そのものの大きさと一致する。
        imageView.contentMode = .scaleToFill
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        show(image)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) は使わない")
    }

    /// 出す画像を決める。同じ画像なら何もしない。
    func show(_ image: UIImage) {
        guard imageView.image !== image else { return }
        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: image.size)
        contentSize = image.size
        // 次の layoutSubviews で倍率を組み直させる。
        sizeWhenScalesWereSet = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }

        if bounds.size != sizeWhenScalesWereSet {
            sizeWhenScalesWereSet = bounds.size
            resetZoomScales()
        }
        centerImage()
    }

    /// **いちばん引いた状態＝レシート全体が入る状態**にそろえる。
    ///
    /// 最小倍率を「画面に収まる倍率」にしてあるので、開いた直後は必ず全体が見える。
    /// それより引けないので、画像を見失うこともない。
    private func resetZoomScales() {
        guard let size = imageView.image?.size, size.width > 0, size.height > 0 else { return }

        let fit = min(bounds.width / size.width, bounds.height / size.height)
        minimumZoomScale = fit
        // 細かい字を読むために6倍まで。ただし大きな写真だと fit が 0.1 ほどになり、
        // その6倍でも等倍に届かない。レシートの小さい字を読む用途なので、
        // 等倍（1）までは必ず寄れるようにしておく。
        maximumZoomScale = max(fit * 6, 1)
        zoomScale = fit
    }

    /// 画面より小さいあいだは真ん中に置く。
    /// これをしないと、引いたときに左上に張り付いて見失う。
    private func centerImage() {
        let extraX = max(bounds.width - contentSize.width, 0) / 2
        let extraY = max(bounds.height - contentSize.height, 0) / 2
        contentInset = UIEdgeInsets(top: extraY, left: extraX, bottom: extraY, right: extraX)
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    // MARK: - 2回叩く

    @objc
    private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard zoomScale <= minimumZoomScale * 1.05 else {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }
        // 叩いた場所へ寄せる。真ん中ではなく、見たいところへ。
        let scale = min(maximumZoomScale, minimumZoomScale * 3)
        let point = recognizer.location(in: imageView)
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        zoom(to: CGRect(origin: origin, size: size), animated: true)
    }
}
