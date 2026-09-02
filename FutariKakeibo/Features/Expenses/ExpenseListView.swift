import SwiftUI

struct ExpenseListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @State private var selectedCategory: ExpenseCategory?
    @State private var mode: EntryEditorView.Kind = .expense
    @State private var editingExpense: Expense?
    @State private var editingIncome: Income?
    @State private var deletingExpense: Expense?

    private var filteredExpenses: [Expense] {
        store.monthlyExpenses.filter { expense in
            let matchesSearch = searchText.isEmpty
                || expense.title.localizedCaseInsensitiveContains(searchText)
                || expense.note.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategory == nil || expense.category == selectedCategory
            return matchesSearch && matchesCategory
        }
    }

    private var filteredIncomes: [Income] {
        store.monthlyIncomes.filter { income in
            searchText.isEmpty
                || income.title.localizedCaseInsensitiveContains(searchText)
                || income.note.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            MonthNavigator(month: store.selectedMonth, onMove: store.moveMonth)
                .padding(.horizontal, 18)

            Picker("表示する種類", selection: $mode) {
                ForEach(EntryEditorView.Kind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 18)
            .padding(.bottom, 4)

            if mode == .expense {
                categoryFilter
                expenseList
            } else {
                incomeList
            }
        }
        .background(AppTheme.background)
        .navigationTitle(mode == .expense ? "支出履歴" : "収入の記録")
        .searchable(text: $searchText, prompt: "内容やメモを検索")
        .sheet(item: $editingExpense) { expense in
            NavigationStack {
                ExpenseEditorView(expense: expense)
            }
        }
        .sheet(item: $editingIncome) { income in
            NavigationStack {
                IncomeEditorView(income: income)
            }
        }
        .alert("この支出を削除しますか？", isPresented: Binding(
            get: { deletingExpense != nil },
            set: { if !$0 { deletingExpense = nil } }
        )) {
            Button("キャンセル", role: .cancel) { deletingExpense = nil }
            Button("削除", role: .destructive) {
                guard let expense = deletingExpense else { return }
                deletingExpense = nil
                Task { await store.deleteExpense(expense) }
            }
        } message: {
            Text("削除後は元に戻せません。共有中の場合はパートナー側からも削除されます。")
        }
    }

    @ViewBuilder
    private var expenseList: some View {
        if let household = store.household, !filteredExpenses.isEmpty {
            List {
                ForEach(filteredExpenses) { expense in
                    Button { editingExpense = expense } label: {
                        ExpenseRow(expense: expense, household: household)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(AppTheme.card)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { deletingExpense = expense } label: {
                            Label("削除", systemImage: "trash")
                        }
                        Button { editingExpense = expense } label: {
                            Label("編集", systemImage: "pencil")
                        }
                        .tint(AppTheme.sage)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        } else {
            ContentUnavailableView(
                searchText.isEmpty ? "この月の支出はありません" : "一致する支出がありません",
                systemImage: searchText.isEmpty ? "calendar.badge.plus" : "magnifyingglass",
                description: Text(searchText.isEmpty ? "追加タブから記録できます。" : "検索条件を変えてみてください。")
            )
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var incomeList: some View {
        if let household = store.household, !filteredIncomes.isEmpty {
            List {
                Section {
                    ForEach(filteredIncomes) { income in
                        Button { editingIncome = income } label: {
                            IncomeRow(income: income, household: household)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(AppTheme.card)
                    }
                } footer: {
                    Text("この月の収入 \(store.monthlyIncomeTotal.yenText)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        } else {
            ContentUnavailableView(
                searchText.isEmpty ? "この月の収入はありません" : "一致する収入がありません",
                systemImage: searchText.isEmpty ? "yensign.circle" : "magnifyingglass",
                description: Text(searchText.isEmpty ? "追加タブの「収入」から記録できます。" : "検索条件を変えてみてください。")
            )
            .frame(maxHeight: .infinity)
        }
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                filterChip(title: "すべて", category: nil)
                ForEach(ExpenseCategory.allCases) { category in
                    filterChip(title: category.displayName, category: category)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
        }
    }

    private func filterChip(title: String, category: ExpenseCategory?) -> some View {
        let selected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? Color.white : AppTheme.deepGreen)
                .background(selected ? AppTheme.terracotta : AppTheme.card)
                .clipShape(Capsule())
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
