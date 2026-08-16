import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                MonthNavigator(month: store.selectedMonth, onMove: store.moveMonth)

                budgetCard
                settlementCard
                categoryCard
                recentCard
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .background(AppTheme.background)
        .navigationTitle("ふたりのホーム")
        .navigationBarTitleDisplayMode(.large)
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
                        .foregroundStyle(AppTheme.deepGreen)
                }
                Spacer()
                Text("予算 \((store.household?.monthlyBudget ?? 0).yenText)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            ProgressView(value: store.budgetProgress)
                .tint(store.budgetProgress >= 0.9 ? AppTheme.terracotta : AppTheme.sage)
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
                .foregroundStyle(AppTheme.deepGreen)

            if store.settlement.amount == 0 {
                Label("いまのところ精算はありません", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(AppTheme.sage)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(store.settlement.payer?.displayName ?? "")
                    Text("→")
                    Text(store.settlement.receiver?.displayName ?? "")
                    Spacer()
                    Text(store.settlement.amount.yenText)
                        .font(.title3.monospacedDigit().bold())
                }
                .foregroundStyle(AppTheme.deepGreen)
                Text("「2人で折半」にした支出だけで計算しています。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .appCard()
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("カテゴリ別")
                .font(.headline)
                .foregroundStyle(AppTheme.deepGreen)

            let totals = LedgerCalculator.categoryTotals(store.monthlyExpenses)
                .sorted { $0.value > $1.value }
            if totals.isEmpty {
                emptyMessage("支出を追加すると内訳が表示されます", icon: "chart.pie")
            } else {
                ForEach(Array(totals.prefix(5)), id: \.key) { category, total in
                    HStack {
                        Label(category.displayName, systemImage: category.systemImage)
                            .foregroundStyle(category.color)
                        Spacer()
                        Text(total.yenText)
                            .monospacedDigit()
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.deepGreen)
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
                .foregroundStyle(AppTheme.deepGreen)

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

    private func emptyMessage(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
    }
}
