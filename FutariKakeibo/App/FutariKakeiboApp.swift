import SwiftUI

@main
struct FutariKakeiboApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task {
                    await store.loadIfNeeded()
                    await store.acceptPendingShareIfNeeded()
                    // 冷えた状態から開いたときは scenePhase の変化が来ないので、ここでも始める。
                    // 二重には回らない（startPeriodicRefresh が見ている）。
                    store.startPeriodicRefresh()
                }
                .onReceive(NotificationCenter.default.publisher(for: .didReceiveCloudKitShare)) { _ in
                    Task { await store.acceptPendingShareIfNeeded() }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                // 閉じたアプリのために通信を続けない。
                store.stopPeriodicRefresh()
                return
            }
            Task {
                await store.acceptPendingShareIfNeeded()
                await store.refreshFromCloudIfConfigured()
            }
            // 相手が保存したことを知らせてくれる仕組みがまだ無いので、
            // 開いているあいだは自分から見に行く。これが無いと、画面を開いたまま
            // 待っている人には相手の記録がいつまでも出てこない。
            store.startPeriodicRefresh()
        }
    }
}
