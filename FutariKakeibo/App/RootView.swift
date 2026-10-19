import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            if store.isLoading {
                VStack(spacing: 14) {
                    WalletSpinner(size: 54)
                        // すぐ下に同じ言葉があるので、読み上げが二重になるのを避ける。
                        .accessibilityHidden(true)
                    Text("読み込み中…")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                }
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
        // 共有のリンクから届いた招待。すでに家計簿があるときは、置き換える前に確かめる。
        .alert(
            "共有の招待を開きました",
            isPresented: Binding(
                get: { store.pendingShareInvitation != nil },
                set: { if !$0 { store.declinePendingShare() } }
            ),
            presenting: store.pendingShareInvitation
        ) { invitation in
            Button("参加する", role: .destructive) {
                Task { await store.confirmPendingShare(invitation) }
            }
            Button("参加しない", role: .cancel) { store.declinePendingShare() }
        } message: { invitation in
            Text(Self.invitationMessage(ownerName: invitation.ownerName))
        }
        .sheet(item: $store.shareConfiguration) { configuration in
            CloudSharingView(configuration: configuration) { message in
                store.errorMessage = message
            }
                .ignoresSafeArea()
        }
    }
}

extension RootView {
    /// 共有のリンクから届いた招待を確かめる文。
    static func invitationMessage(ownerName: String?) -> String {
        let whose = ownerName.map { "\($0)さんの家計簿" } ?? "この家計簿"
        return "\(whose)に参加しますか？参加すると、いまの家計簿は置き換わり、"
            + "このiPhoneの中だけにある記録は消えます。知らない人から届いたリンクなら、参加しないでください。"
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

    @EnvironmentObject private var store: AppStore
    @State private var selection: Tab = .dashboard
    /// 通知を押して開いた支出。
    @State private var notifiedExpense: Expense?

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
        .tint(AppTheme.accent)
        // 通知を押してアプリが起動したときは、この画面が出たときに開く。
        .onAppear(perform: openNotificationRoute)
        .onChange(of: store.pendingNotificationRoute) { _, _ in openNotificationRoute() }
        .sheet(item: $notifiedExpense) { expense in
            NavigationStack {
                ExpenseEditorView(expense: expense)
            }
        }
    }

    /// 通知を押して開いたとき。その支出を開く。見つからなければ（もう消された・何件かまとめた通知）履歴を開く。
    private func openNotificationRoute() {
        guard let route = store.pendingNotificationRoute else { return }
        store.pendingNotificationRoute = nil
        selection = .history
        if case let .expense(id) = route, let expense = store.expenses.first(where: { $0.id == id }) {
            notifiedExpense = expense
        }
    }
}
