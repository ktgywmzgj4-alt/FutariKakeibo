import Charts
import SwiftUI

/// 月ごとの振り返り。推移・カテゴリ内訳・2人の負担をまとめて見る。
struct ReportView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                ScreenTitle("レポート")
                MonthNavigator(month: store.selectedMonth, onMove: store.moveMonth)

                let report = store.monthlyReport
                summaryCard(report)
                trendCard(report)
                categoryCard(report)
                memberCard(report)
                highlightCard(report)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .background(AppTheme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refreshFromCloudIfConfigured() }
    }

    private func summaryCard(_ report: MonthlyReport) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("この月の合計")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)

            Text(report.total.yenText)
                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(AppTheme.ink)

            HStack(spacing: 7) {
                Image(systemName: differenceIcon(report))
                    .font(.caption.bold())
                Text(differenceText(report))
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(differenceColor(report))

            Divider().opacity(0.55)

            HStack {
                metric("1日あたり", value: report.dailyAverage.yenText)
                Spacer()
                metric("記録した件数", value: "\(report.expenseCount)件")
            }

            if report.income > 0 {
                Divider().opacity(0.55)

                HStack {
                    metric("収入", value: report.income.yenText)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("収支")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        Text(report.balance.balance.yenText)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(report.balance.isNegative ? AppTheme.danger : AppTheme.positive)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private func trendCard(_ report: MonthlyReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("6か月の推移")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            let hasIncome = report.trend.contains { $0.income > 0 }
            if report.trend.allSatisfy({ $0.expense == 0 && $0.income == 0 }) {
                emptyMessage("記録を追加すると推移が表示されます", icon: "chart.bar")
            } else {
                Chart {
                    ForEach(report.trend) { item in
                        BarMark(
                            x: .value("月", monthLabel(item.month)),
                            y: .value("金額", item.expense)
                        )
                        .foregroundStyle(by: .value("種別", "支出"))
                        .position(by: .value("種別", "支出"))
                        .cornerRadius(5)
                    }
                    if hasIncome {
                        ForEach(report.trend) { item in
                            BarMark(
                                x: .value("月", monthLabel(item.month)),
                                y: .value("金額", item.income)
                            )
                            .foregroundStyle(by: .value("種別", "収入"))
                            .position(by: .value("種別", "収入"))
                            .cornerRadius(5)
                        }
                    }
                }
                .chartForegroundStyleScale([
                    "支出": AppTheme.accent,
                    "収入": AppTheme.positive
                ])
                .chartLegend(hasIncome ? .visible : .hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Int.self) {
                                Text(shortYen(amount))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 168)
                .accessibilityLabel(hasIncome ? "月ごとの収入と支出の推移" : "月ごとの支出の推移")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private func categoryCard(_ report: MonthlyReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("カテゴリの内訳")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            if report.categories.isEmpty {
                emptyMessage("この月の支出はまだありません", icon: "chart.pie")
            } else {
                Chart(Array(report.categories.prefix(6))) { slice in
                    SectorMark(
                        angle: .value("金額", slice.total),
                        innerRadius: .ratio(0.58),
                        angularInset: 1.5
                    )
                    .foregroundStyle(slice.category.color)
                }
                .frame(height: 186)
                .accessibilityLabel("カテゴリ別の割合")

                VStack(spacing: 9) {
                    ForEach(report.categories.prefix(6)) { slice in
                        HStack(spacing: 9) {
                            Circle()
                                .fill(slice.category.color)
                                .frame(width: 10, height: 10)
                            Text(slice.category.displayName)
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            Text(percentText(slice.share))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(AppTheme.secondaryText)
                            Text(slice.total.yenText)
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private func memberCard(_ report: MonthlyReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("2人の支払い")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            if report.total == 0 {
                emptyMessage("支出を追加すると2人の負担が表示されます", icon: "person.2")
            } else {
                ForEach(report.members) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.member.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            Text(percentText(item.share))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(AppTheme.secondaryText)
                            Text(item.paid.yenText)
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                        }
                        ProgressView(value: min(max(item.share, 0), 1))
                            .tint(item.member.role == .owner ? AppTheme.accent : AppTheme.positive)
                            .accessibilityLabel("\(item.member.displayName)が支払った割合")
                            .accessibilityValue(percentText(item.share))
                    }
                }

                Text("これは「誰が立て替えたか」の割合です。折半の精算はホーム画面で確認できます。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private func highlightCard(_ report: MonthlyReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("この月で一番大きい支出")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            if let expense = report.largestExpense, let household = store.household {
                ExpenseRow(expense: expense, household: household)
            } else {
                emptyMessage("まだ記録がありません", icon: "sparkles")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    // MARK: - 表示の組み立て

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(AppTheme.ink)
        }
    }

    private func emptyMessage(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
    }

    private func differenceText(_ report: MonthlyReport) -> String {
        guard report.previousTotal > 0 else { return "前の月の記録がありません" }
        if report.difference == 0 { return "前の月と同じです" }
        let word = report.difference > 0 ? "増えました" : "減りました"
        return "前の月より \(abs(report.difference).yenText) \(word)"
    }

    private func differenceIcon(_ report: MonthlyReport) -> String {
        guard report.previousTotal > 0, report.difference != 0 else { return "equal.circle.fill" }
        return report.difference > 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill"
    }

    private func differenceColor(_ report: MonthlyReport) -> Color {
        guard report.previousTotal > 0, report.difference != 0 else { return AppTheme.secondaryText }
        return report.difference > 0 ? AppTheme.accent : AppTheme.positive
    }

    private func isSelectedMonth(_ month: Date) -> Bool {
        Calendar.current.isDate(month, equalTo: store.selectedMonth, toGranularity: .month)
    }

    private func monthLabel(_ month: Date) -> String {
        month.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: "ja_JP")))
    }

    private func percentText(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }

    /// グラフの目盛りを短く読ませる。1万円以上は「5.2万」のように丸める。
    private func shortYen(_ amount: Int) -> String {
        if amount >= 10_000 {
            let man = Double(amount) / 10_000
            return man >= 10
                ? "\(Int(man.rounded()))万"
                : String(format: "%.1f万", man)
        }
        if amount >= 1_000 {
            return "\(amount / 1_000)千"
        }
        return "\(amount)"
    }
}
