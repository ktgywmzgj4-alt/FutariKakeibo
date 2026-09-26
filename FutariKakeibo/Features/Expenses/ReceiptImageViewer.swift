import SwiftUI
import UIKit

/// レシートを大きく見る画面。指を広げると拡大でき、2回叩くと元に戻る。
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

    private static let maxScale: CGFloat = 5

    @State private var phase: Phase = .loading
    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    loadingView
                case let .ready(image):
                    imageView(image)
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

    private func imageView(_ image: UIImage) -> some View {
        GeometryReader { proxy in
            // **枠ごと大きくしてスクロールさせると、中身は左上から伸びる。**
            // 画像は真ん中を軸に拡大し、見たい場所へは指で動かして寄せる。
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    SimultaneousGesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = clamped(committedScale * value.magnification)
                                offset = clampedOffset(offset, in: proxy.size)
                            }
                            .onEnded { _ in
                                committedScale = scale
                                committedOffset = offset
                            },
                        DragGesture()
                            .onChanged { value in
                                let moved = CGSize(
                                    width: committedOffset.width + value.translation.width,
                                    height: committedOffset.height + value.translation.height
                                )
                                offset = clampedOffset(moved, in: proxy.size)
                            }
                            .onEnded { _ in
                                committedOffset = offset
                            }
                    )
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        let zoomedIn = scale > 1.05
                        scale = zoomedIn ? 1 : 2.5
                        committedScale = scale
                        // 等倍に戻すときは位置も戻す。端に寄ったまま縮むと見失う。
                        offset = zoomedIn ? .zero : clampedOffset(offset, in: proxy.size)
                        committedOffset = offset
                    }
                }
                .accessibilityLabel("レシートの画像")
                .accessibilityHint("指を広げると拡大、2回叩くと元に戻ります")
        }
        .clipped()
    }

    /// 画像を動かせる範囲。拡大してはみ出した分の半分まで。
    /// これ以上動かせると、画面から画像が消えて戻せなくなる。
    private func clampedOffset(_ value: CGSize, in size: CGSize) -> CGSize {
        let overflowX = max(size.width * (scale - 1) / 2, 0)
        let overflowY = max(size.height * (scale - 1) / 2, 0)
        return CGSize(
            width: min(max(value.width, -overflowX), overflowX),
            height: min(max(value.height, -overflowY), overflowY)
        )
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

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 1), Self.maxScale)
    }

    private func load() async {
        phase = .loading
        scale = 1
        committedScale = 1
        offset = .zero
        committedOffset = .zero
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
