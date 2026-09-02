import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            if store.isLoading {
                ProgressView("読み込み中…")
                    .tint(AppTheme.terracotta)
            } else if store.household == nil {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .preferredColorScheme(.light)
        .alert(
            "確認してください",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("閉じる", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .sheet(item: $store.shareConfiguration) { configuration in
            CloudSharingView(configuration: configuration) { message in
                store.errorMessage = message
            }
                .ignoresSafeArea()
        }
    }
}

private struct MainTabView: View {
    enum Tab: Hashable {
        case dashboard
        case history
        case add
        case report
        case settings
    }

    @State private var selection: Tab = .dashboard

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { DashboardView() }
                .tabItem { Label("ホーム", systemImage: "house.fill") }
                .tag(Tab.dashboard)

            NavigationStack { ExpenseListView() }
                .tabItem { Label("履歴", systemImage: "list.bullet.rectangle") }
                .tag(Tab.history)

            NavigationStack {
                EntryEditorView { selection = .dashboard }
            }
            .tabItem { Label("追加", systemImage: "plus.circle.fill") }
            .tag(Tab.add)

            NavigationStack { ReportView() }
                .tabItem { Label("レポート", systemImage: "chart.bar.xaxis") }
                .tag(Tab.report)

            NavigationStack { SettingsView() }
                .tabItem { Label("設定", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .tint(AppTheme.terracotta)
    }
}
