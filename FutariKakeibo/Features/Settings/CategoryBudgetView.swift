import SwiftUI

/// カテゴリごとの月予算を決める画面。0円にしたカテゴリは予算なしとして扱う。
struct CategoryBudgetView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var amountTexts: [ExpenseCategory: String] = [:]
    @State private var initialized = false
    @FocusState private var focusedCategory: ExpenseCategory?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                summaryCard
                categoryCard
                saveButton
            }
            .padding(18)
            .padding(.bottom, 26)
        }
        .background(AppTheme.background)
        .navigationTitle("カテゴリ別予算")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") { focusedCategory = nil }
            }
        }
        .onAppear(perform: loadFields)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("予算の合計", systemImage: "chart.pie.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            HStack(alignment: .firstTextBaseline) {
                Text(enteredTotal.yenText)
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text("月予算 \(monthlyBudget.yenText)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            if monthlyBudget > 0 && enteredTotal > monthlyBudget {
                Label(
                    "カテゴリ予算の合計が月予算を \((enteredTotal - monthlyBudget).yenText) 超えています。",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.danger)
            } else {
                Text("入力しなかったカテゴリは、予算なしとして扱います。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var categoryCard: some View {
        VStack(spacing: 14) {
            ForEach(ExpenseCategory.allCases) { category in
                VStack(spacing: 7) {
                    HStack(spacing: 11) {
                        Image(systemName: category.systemImage)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(category.color)
                            .clipShape(Circle())
                            .accessibilityHidden(true)

                        Text(category.displayName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)

                        Spacer(minLength: 8)

                        HStack(spacing: 3) {
                            Text("¥").foregroundStyle(AppTheme.secondaryText)
                            TextField("0", text: binding(for: category))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .frame(width: 96)
                                .focused($focusedCategory, equals: category)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(AppTheme.background.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    HStack {
                        Text("今月の支出 \(spent(in: category).yenText)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        Spacer()
                    }
                }

                if category != ExpenseCategory.allCases.last {
                    Divider().opacity(0.55)
                }
            }
        }
        .appCard()
    }

    private var saveButton: some View {
        Button(action: save) {
            Text("カテゴリ別予算を保存")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(.white)
                .background(AppTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var monthlyBudget: Int {
        store.household?.monthlyBudget ?? 0
    }

    private var enteredTotal: Int {
        ExpenseCategory.allCases.reduce(0) { $0 + amount(for: $1) }
    }

    private func amount(for category: ExpenseCategory) -> Int {
        Int((amountTexts[category] ?? "").filter(\.isNumber)) ?? 0
    }

    private func spent(in category: ExpenseCategory) -> Int {
        LedgerCalculator.total(store.monthlyExpenses.filter { $0.category == category })
    }

    private func binding(for category: ExpenseCategory) -> Binding<String> {
        Binding(
            get: { amountTexts[category] ?? "" },
            set: { amountTexts[category] = $0 }
        )
    }

    private func loadFields() {
        guard !initialized, let household = store.household else { return }
        initialized = true
        for budget in household.categoryBudgets where budget.amount > 0 {
            amountTexts[budget.category] = String(budget.amount)
        }
    }

    private func save() {
        focusedCategory = nil
        let budgets = ExpenseCategory.allCases.compactMap { category -> CategoryBudget? in
            let value = amount(for: category)
            return value > 0 ? CategoryBudget(category: category, amount: value) : nil
        }
        Task {
            await store.updateCategoryBudgets(budgets)
            dismiss()
        }
    }
}
