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
                }
                .onReceive(NotificationCenter.default.publisher(for: .didReceiveCloudKitShare)) { _ in
                    Task { await store.acceptPendingShareIfNeeded() }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await store.acceptPendingShareIfNeeded()
                await store.refreshFromCloudIfConfigured()
            }
        }
    }
}
