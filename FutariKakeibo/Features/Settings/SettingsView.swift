import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var householdName = ""
    @State private var budgetText = ""
    @State private var members: [Member] = []
    @State private var exportFile: ExportFile?
    @State private var exportURLPendingCleanup: URL?
    @State private var showPrivacy = false
    @State private var showDeleteConfirmation = false
    @State private var initialized = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ScreenTitle("設定")
                householdCard
                planningCard
                cloudCard
                dataCard
                aboutCard
            }
            .padding(18)
            .padding(.bottom, 26)
        }
        .background(AppTheme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadFields)
        .sheet(item: $exportFile, onDismiss: cleanupExportFile) { file in
            ActivityView(items: [file.url])
        }
        .sheet(isPresented: $showPrivacy) {
            PrivacySummaryView()
        }
        .alert("このiPhone内のデータを削除しますか？", isPresented: $showDeleteConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                Task { await store.eraseLocalData() }
            }
        } message: {
            Text("この操作は元に戻せません。iCloud共有中のデータは削除せず、このiPhoneとの接続だけを解除します。")
        }
    }

    private var householdCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("ふたりの設定", icon: "person.2.fill")

            labeledField("家計の名前", text: $householdName)

            ForEach($members) { $member in
                labeledField(member.role == .owner ? "あなたの呼び名" : "パートナーの呼び名", text: $member.displayName)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("月予算")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                HStack {
                    Text("¥")
                    TextField("100000", text: $budgetText)
                        .keyboardType(.numberPad)
                        .monospacedDigit()
                }
                .padding(11)
                .background(AppTheme.background.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Button("設定を保存") {
                Task {
                    await store.updateHousehold(
                        name: householdName,
                        monthlyBudget: Int(budgetText.filter(\.isNumber)) ?? 0,
                        members: members
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .appCard()
    }

    private var planningCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("予算と自動入力", icon: "wand.and.stars")

            NavigationLink {
                RecurringExpenseListView()
            } label: {
                settingsRow("定期支出（家賃・サブスク）", icon: "repeat.circle.fill")
            }
            .buttonStyle(.plain)

            Divider()

            NavigationLink {
                CategoryBudgetView()
            } label: {
                settingsRow("カテゴリ別予算", icon: "chart.pie.fill")
            }
            .buttonStyle(.plain)

            Text(planningSummary)
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .appCard()
    }

    private var planningSummary: String {
        let active = store.recurringExpenses.filter(\.isActive)
        guard !active.isEmpty else {
            return "家賃や電気代を登録しておくと、毎月自動で支出に追加されます。"
        }
        let total = active.reduce(0) { $0 + $1.amount }
        return "毎月 \(active.count) 件・\(total.yenText) を自動で計上します。"
    }

    private var cloudCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("ふたりで共有", icon: "icloud.fill")

            Label(store.syncState.label, systemImage: syncIcon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(syncColor)

            Text(store.household?.cloudLocation == nil
                 ? "合言葉をひとつ相手に伝えるだけで、同じ家計簿を2人で使えます。"
                 : "この家計簿は2人で共有しています。どちらが記録しても、もう一方に届きます。")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)

            NavigationLink {
                SharingView()
            } label: {
                settingsRow(
                    store.household?.cloudLocation == nil ? "共有をはじめる" : "共有の設定",
                    icon: "person.2.badge.key.fill"
                )
            }
            .buttonStyle(.plain)

            if store.household?.cloudLocation != nil {
                Divider()

                Button {
                    Task { await store.refreshFromCloudIfConfigured() }
                } label: {
                    settingsRow("今すぐ同期", icon: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.plain)
                .disabled(store.syncState == .syncing)
            }
        }
        .appCard()
    }

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("データ管理", icon: "externaldrive.fill")

            Button {
                do {
                    let url = try store.exportCSV()
                    exportURLPendingCleanup = url
                    exportFile = ExportFile(url: url)
                } catch {
                    store.errorMessage = error.localizedDescription
                }
            } label: {
                settingsRow("CSVを書き出す", icon: "square.and.arrow.up")
            }
            .buttonStyle(.plain)

            Divider()

            Button { showPrivacy = true } label: {
                settingsRow("データとプライバシー", icon: "lock.shield.fill")
            }
            .buttonStyle(.plain)

            Divider()

            Button(role: .destructive) { showDeleteConfirmation = true } label: {
                settingsRow("このiPhone内のデータを削除", icon: "trash.fill", color: AppTheme.danger)
            }
            .buttonStyle(.plain)
        }
        .appCard()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("ふたり家計簿", icon: "house.and.flag.fill")
            Text("Version 0.1.0 (1)")
                .font(.footnote.monospaced())
                .foregroundStyle(AppTheme.secondaryText)
            Text("広告・課金機能はまだ実装していません。")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .appCard()
    }

    private var syncIcon: String {
        switch store.syncState {
        case .localOnly: "iphone"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .synced: "checkmark.icloud.fill"
        case .failed: "exclamationmark.icloud.fill"
        }
    }

    private var syncColor: Color {
        switch store.syncState {
        case .failed: AppTheme.danger
        case .synced: AppTheme.positive
        default: AppTheme.secondaryText
        }
    }

    private func loadFields() {
        guard !initialized, let household = store.household else { return }
        initialized = true
        householdName = household.name
        budgetText = String(household.monthlyBudget)
        members = household.members
    }

    private func cleanupExportFile() {
        guard let url = exportURLPendingCleanup else { return }
        try? FileManager.default.removeItem(at: url)
        exportURLPendingCleanup = nil
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(AppTheme.ink)
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            TextField(label, text: text)
                .padding(11)
                .background(AppTheme.background.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func settingsRow(_ title: String, icon: String, color: Color = AppTheme.ink) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
        }
        .foregroundStyle(color)
        .contentShape(Rectangle())
    }
}
