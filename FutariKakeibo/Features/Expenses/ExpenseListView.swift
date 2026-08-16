import SwiftUI

struct ExpenseListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @State private var selectedCategory: ExpenseCategory?
    @State private var editingExpense: Expense?
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

    var body: some View {
        VStack(spacing: 0) {
            MonthNavigator(month: store.selectedMonth, onMove: store.moveMonth)
                .padding(.horizontal, 18)

            categoryFilter

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
        .background(AppTheme.background)
        .navigationTitle("支出履歴")
        .searchable(text: $searchText, prompt: "内容やメモを検索")
        .sheet(item: $editingExpense) { expense in
            NavigationStack {
                ExpenseEditorView(expense: expense)
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
