import SwiftUI

/// 家賃やサブスクのひな形を一覧・管理する画面。
struct RecurringExpenseListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editingTemplate: RecurringExpense?
    @State private var isAddingTemplate = false
    @State private var deletingTemplate: RecurringExpense?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                summaryCard

                if store.recurringExpenses.isEmpty {
                    emptyCard
                } else {
                    ForEach(store.recurringExpenses) { template in
                        templateCard(template)
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 26)
        }
        .background(AppTheme.background)
        .navigationTitle("定期支出")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAddingTemplate = true } label: {
                    Label("追加", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingTemplate) {
            NavigationStack { RecurringExpenseEditorView() }
        }
        .sheet(item: $editingTemplate) { template in
            NavigationStack { RecurringExpenseEditorView(template: template) }
        }
        .alert("この定期支出を削除しますか？", isPresented: Binding(
            get: { deletingTemplate != nil },
            set: { if !$0 { deletingTemplate = nil } }
        )) {
            Button("キャンセル", role: .cancel) { deletingTemplate = nil }
            Button("削除", role: .destructive) {
                guard let template = deletingTemplate else { return }
                deletingTemplate = nil
                Task { await store.deleteRecurringExpense(template) }
            }
        } message: {
            Text("次の月からは自動で計上されなくなります。すでに計上済みの支出は履歴に残ります。")
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("毎月の固定費", systemImage: "repeat.circle.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            Text(monthlyFixedTotal.yenText)
                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(AppTheme.ink)
                .spectrumEdge(2)

            Text("有効な定期支出 \(store.recurringExpenses.filter(\.isActive).count) 件の合計です。指定した日になると自動で支出に追加されます。")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(AppTheme.positive)
            Text("まだ定期支出がありません")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text("家賃、電気代、通信費、動画配信などを登録しておくと、毎月の入力がいらなくなります。")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.secondaryText)
            Button { isAddingTemplate = true } label: {
                Label("定期支出を追加", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
        }
        .frame(maxWidth: .infinity)
        .appCard()
    }

    private func templateCard(_ template: RecurringExpense) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 13) {
                Image(systemName: template.category.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(template.isActive ? template.category.color : AppTheme.secondaryText)
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(template.scheduleDescription)
                        Text("•")
                        Text(payerName(for: template))
                        if template.splitMethod == .personal {
                            Text("個人")
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.positiveSoft)
                                .clipShape(Capsule())
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer(minLength: 8)

                Text(template.amount.yenText)
                    .font(.body.monospacedDigit().weight(.bold))
                    .foregroundStyle(template.isActive ? AppTheme.ink : AppTheme.secondaryText)
            }

            if let endMonth = template.endMonth {
                Text("\(monthText(endMonth))まで")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Divider().opacity(0.55)

            HStack {
                Toggle("有効", isOn: Binding(
                    get: { template.isActive },
                    set: { newValue in
                        Task { await store.setRecurringExpense(template, isActive: newValue) }
                    }
                ))
                .labelsHidden()
                .tint(AppTheme.positive)

                Text(template.isActive ? "有効" : "停止中")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)

                Spacer()

                Button { editingTemplate = template } label: {
                    Label("編集", systemImage: "pencil")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.positive)

                Button(role: .destructive) { deletingTemplate = template } label: {
                    Label("削除", systemImage: "trash")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.danger)
            }
        }
        .appCard()
    }

    private var monthlyFixedTotal: Int {
        store.recurringExpenses.filter(\.isActive).reduce(0) { $0 + $1.amount }
    }

    private func payerName(for template: RecurringExpense) -> String {
        store.household?.member(id: template.paidByMemberID)?.displayName ?? "不明"
    }

    private func monthText(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "ja_JP")))
    }
}
