import SwiftUI
import UIKit

/// 引っ張って更新したときの待ち方。
///
/// 引っ張る操作、二重に起動しないこと、終わるまで待つことは SwiftUI の `.refreshable` に
/// そのまま任せる。変えるのは**見た目だけ**で、標準のくるくるを透明にして
/// （`hideSystemIndicator`）、同じ場所でお財布を回す（`walletRefreshable`）。
enum PullToRefresh {
    /// 回して待つ上限。
    ///
    /// CloudKit の問い合わせは、通信が詰まると1回60秒まで待つ。そのまま待つと
    /// 回りっぱなしに見えるので、ここで区切る。ふだんの取得は1〜3秒で終わる。
    static let timeout: Duration = .seconds(15)

    /// `work` が終わるか `timeout` が来るか、早いほうで戻る。`work` が終わっていれば true。
    ///
    /// **時間切れでも `work` は取り消さない。** 取り消すと CloudKit のやりとりが途中で切れ、
    /// 設定画面に「同期できませんでした」と出てしまう。裏で終われば、その結果が画面に出る。
    @MainActor
    static func run(
        timeout: Duration = PullToRefresh.timeout,
        _ work: @escaping @Sendable () async -> Void
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let race = Race(continuation)
            Task { @MainActor in
                await work()
                race.finish(true)
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                race.finish(false)
            }
        }
    }

    /// 標準のくるくるを透明にする。起動時に1回だけ呼ぶ（`FutariKakeiboApp`）。
    ///
    /// SwiftUI の `.refreshable` は中で `UIRefreshControl` を使っていて、その色は
    /// UIAppearance でしか変えられない。このアプリで引っ張って更新するのは
    /// `walletRefreshable` を付けた画面だけなので、アプリ全体に効かせてよい。
    @MainActor
    static func hideSystemIndicator() {
        UIRefreshControl.appearance().tintColor = .clear
    }
}

/// 先に終わったほうだけが返事をする。もう片方は何もしない。
@MainActor
private final class Race {
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func finish(_ finished: Bool) {
        continuation?.resume(returning: finished)
        continuation = nil
    }
}

/// 引っ張って更新し、待つあいだお財布を回す。`.refreshable` の代わりに使う。
private struct WalletRefreshable: ViewModifier {
    let action: @Sendable () async -> Void

    @State private var isRefreshing = false

    func body(content: Content) -> some View {
        content
            .refreshable { await refresh() }
            .overlay(alignment: .top) {
                ZStack {
                    if isRefreshing {
                        WalletSpinner(size: 34, label: "更新中")
                            .transition(.opacity)
                    }
                }
                // 標準のくるくるが出る場所（上に空く約60ポイントの隙間）の真ん中あたり。
                .padding(.top, 13)
                // 現れる・消えるだけをなめらかにする。中身（一覧）の動きには触れない。
                .animation(.easeOut(duration: 0.2), value: isRefreshing)
                // 指の操作はすべて下の画面へ通す。
                .allowsHitTesting(false)
            }
    }

    @MainActor
    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        _ = await PullToRefresh.run(action)
    }
}

extension View {
    /// 引っ張って更新する。待つあいだ、標準のくるくるの代わりにお財布が回る。
    ///
    /// 一覧（`List`）やスクロール（`ScrollView`）そのものに付けること。
    /// お財布はこの部品の上端に出るので、上に別の部品が並ぶ画面で外側に付けると、
    /// その部品の上に重なってしまう。
    func walletRefreshable(_ action: @escaping @Sendable () async -> Void) -> some View {
        modifier(WalletRefreshable(action: action))
    }
}
