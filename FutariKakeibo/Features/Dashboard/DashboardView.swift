import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.cardSpacing) {
                VStack(alignment: .leading, spacing: 10) {
                    ScreenTitle("ふたりのホーム")
                    memberRow
                }
                .padding(.bottom, 2)

                MonthNavigator(month: store.selectedMonth, onMove: store.moveMonth)

                recurringNoticeCard
                budgetCard
                balanceCard
                settlementCard
                categoryBudgetCard
                upcomingRecurringCard
                categoryCard
                recentCard
            }
            .padding(.horizontal, AppTheme.screenPadding)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .background(AppTheme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refreshFromCloudIfConfigured() }
    }

    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今月の支出")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(store.monthlyTotal.yenText)
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(AppTheme.ink)
                }
                Spacer()
                Text("予算 \((store.household?.monthlyBudget ?? 0).yenText)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            // 通常の予算バーはブルー。超えたときだけ赤にする。
            ProgressView(value: store.budgetProgress)
                .tint(store.monthlyTotal > (store.household?.monthlyBudget ?? 0)
                    ? AppTheme.danger
                    : AppTheme.accent)
                .scaleEffect(x: 1, y: 1.6)
                .accessibilityLabel("予算の使用率")
                .accessibilityValue("\(Int(store.budgetProgress * 100))パーセント")

            let budget = store.household?.monthlyBudget ?? 0
            if budget <= 0 {
                Text("設定で月予算を入力してください")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                let remaining = max(budget - store.monthlyTotal, 0)
                Text(remaining > 0 ? "あと \(remaining.yenText) 使えます" : "予算に達しました")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(store.monthlyTotal > budget
                        ? AppTheme.danger
                        : AppTheme.secondaryText)
            }
        }
        .appCard()
    }

    private var settlementCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("今月の精算", systemImage: "arrow.left.arrow.right.circle.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            if store.settlement.amount == 0 {
                Label("いまのところ精算はありません", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(AppTheme.positive)
            } else {
                // 精算の2人にも、ホーム上部と同じ人物の色を使う。
                HStack(spacing: 10) {
                    if let payer = store.settlement.payer {
                        MemberTag(name: payer.displayName, color: memberColor(payer.id), avatarSize: 24)
                    }
                    Image(systemName: "arrow.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                    if let receiver = store.settlement.receiver {
                        MemberTag(name: receiver.displayName, color: memberColor(receiver.id), avatarSize: 24)
                    }
                    Spacer(minLength: 8)
                    Text(store.settlement.amount.yenText)
                        .font(.title3.monospacedDigit().bold())
                        .foregroundStyle(AppTheme.ink)
                }
                Text("「2人で折半」にした支出だけで計算しています。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .appCard()
    }

    private func memberColor(_ id: UUID?) -> Color {
        store.household?.color(of: id) ?? AppTheme.accent
    }

    /// 見出しのすぐ下。いま誰の家計を見ているかを、色と一緒に示す。
    /// 1人で使っている場合は1人だけ出す。架空の相手は作らない。
    @ViewBuilder
    private var memberRow: some View {
        if let household = store.household, !household.members.isEmpty {
            HStack(spacing: 16) {
                ForEach(household.members) { member in
                    MemberTag(
                        name: member.displayName,
                        color: household.color(of: member.id),
                        avatarSize: 30
                    )
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("カテゴリ別")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            let totals = LedgerCalculator.categoryTotals(store.monthlyExpenses)
                .sorted { $0.value > $1.value }
            if totals.isEmpty {
                emptyMessage("支出を追加すると内訳が表示されます", icon: "chart.pie")
            } else {
                ForEach(Array(totals.prefix(5)), id: \.key) { category, total in
                    HStack(spacing: 10) {
                        Image(systemName: category.systemImage)
                            .font(.subheadline)
                            .foregroundStyle(category.color)
                            .frame(width: 22)
                        Text(category.displayName)
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                        Text(total.yenText)
                            .monospacedDigit()
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.ink)
                    }
                }
            }
        }
        .appCard()
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("最近の支出")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            if let household = store.household, !store.monthlyExpenses.isEmpty {
                ForEach(store.monthlyExpenses.prefix(4)) { expense in
                    ExpenseRow(expense: expense, household: household)
                    if expense.id != store.monthlyExpenses.prefix(4).last?.id {
                        Divider().opacity(0.55)
                    }
                }
            } else {
                emptyMessage("最初の支出を追加してみましょう", icon: "plus.circle")
            }
        }
        .appCard()
    }

    @ViewBuilder
    private var balanceCard: some View {
        let balance = store.monthlyBalance
        if balance.income > 0 {
            VStack(alignment: .leading, spacing: 13) {
                Label("今月の収支", systemImage: "arrow.up.arrow.down.circle.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                HStack(alignment: .firstTextBaseline) {
                    Text(balance.balance.yenText)
                        .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(balance.isNegative ? AppTheme.danger : AppTheme.ink)
                    Spacer()
                    if let rate = balance.savingsRate, rate > 0 {
                        Text("貯蓄率 \(Int((rate * 100).rounded()))%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("収入")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        Text(balance.income.yenText)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("支出")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        Text(balance.expense.yenText)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                    }
                }

                if balance.isNegative {
                    Text("この月は収入より支出が多くなっています。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.danger)
                }
            }
            .appCard()
        }
    }

    @ViewBuilder
    private var recurringNoticeCard: some View {
        if store.lastRecurringInsertCount > 0 {
            HStack(spacing: 11) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.positive)
                Text("定期支出を \(store.lastRecurringInsertCount) 件、自動で追加しました")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 8)
                Button("閉じる") { store.lastRecurringInsertCount = 0 }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(14)
            .background(AppTheme.positiveSoft.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private var categoryBudgetCard: some View {
        let statuses = store.categoryBudgetStatuses
        if !statuses.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("カテゴリ別予算")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    if let over = statuses.first(where: \.isOverBudget) {
                        Label("\(over.category.displayName)が超過", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.danger)
                    }
                }

                ForEach(statuses.prefix(4)) { status in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(status.category.displayName, systemImage: status.category.systemImage)
                                .font(.subheadline)
                                .foregroundStyle(status.category.color)
                            Spacer()
                            Text("\(status.spent.yenText) / \(status.budget.yenText)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(status.isOverBudget ? AppTheme.danger : AppTheme.secondaryText)
                        }
                        ProgressView(value: status.progress)
                            .tint(status.isOverBudget ? AppTheme.danger : status.category.color)
                            .accessibilityLabel("\(status.category.displayName)の予算使用率")
                            .accessibilityValue("\(Int(status.progress * 100))パーセント")
                    }
                }
            }
            .appCard()
        }
    }

    @ViewBuilder
    private var upcomingRecurringCard: some View {
        let occurrences = store.upcomingRecurringOccurrences
        if !occurrences.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("この先の定期支出", systemImage: "repeat.circle.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                ForEach(occurrences.prefix(3)) { occurrence in
                    HStack(spacing: 9) {
                        Text(occurrence.date.formatted(.dateTime.month().day()))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                        Text(occurrence.template.title)
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                        Text(occurrence.template.amount.yenText)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                    }
                    .font(.subheadline)
                }

                Text("その日になると自動で支出に追加されます。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .appCard()
        }
    }

    private func emptyMessage(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
    }
}
