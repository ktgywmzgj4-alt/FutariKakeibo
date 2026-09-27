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
            ProgressView().tint(AppTheme.accent)
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

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
            scrollView.zoomScale = scrollView.minimumZoomScale
        }
        context.coordinator.layout(in: scrollView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            center(in: scrollView)
        }

        /// 画面の大きさが決まってから、画像をそこにぴったり収める。
        func layout(in scrollView: UIScrollView) {
            guard let imageView, scrollView.bounds.width > 0, scrollView.bounds.height > 0 else {
                return
            }
            guard imageView.frame.size != scrollView.bounds.size || scrollView.zoomScale == 1 else {
                return
            }
            imageView.frame = CGRect(origin: .zero, size: scrollView.bounds.size)
            scrollView.contentSize = scrollView.bounds.size
            center(in: scrollView)
        }

        /// 画面より小さいあいだは真ん中に置く。
        /// これをしないと、縮めたとき左上に張り付いて見失う。
        private func center(in scrollView: UIScrollView) {
            guard let imageView else { return }
            let extraX = max(scrollView.bounds.width - imageView.frame.width, 0) / 2
            let extraY = max(scrollView.bounds.height - imageView.frame.height, 0) / 2
            scrollView.contentInset = UIEdgeInsets(
                top: extraY, left: extraX, bottom: extraY, right: extraX
            )
        }

        @objc
        func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            guard scrollView.zoomScale <= scrollView.minimumZoomScale * 1.05 else {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }
            // 叩いた場所へ寄せる。真ん中ではなく、見たいところへ。
            let scale = min(scrollView.maximumZoomScale, 3)
            let point = recognizer.location(in: imageView)
            let size = CGSize(
                width: scrollView.bounds.width / scale,
                height: scrollView.bounds.height / scale
            )
            let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
            scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
        }
    }
}
