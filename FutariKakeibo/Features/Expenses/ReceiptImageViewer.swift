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
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: proxy.size.width * scale,
                        height: proxy.size.height * scale
                    )
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = clamped(committedScale * value.magnification)
                            }
                            .onEnded { _ in
                                committedScale = scale
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scale = scale > 1.05 ? 1 : 2.5
                            committedScale = scale
                        }
                    }
                    .accessibilityLabel("レシートの画像")
            }
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

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 1), Self.maxScale)
    }

    private func load() async {
        phase = .loading
        scale = 1
        committedScale = 1
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
