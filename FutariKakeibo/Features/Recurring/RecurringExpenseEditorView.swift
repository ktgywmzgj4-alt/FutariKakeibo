import SwiftUI

/// 定期支出のひな形を作る・直す画面。
struct RecurringExpenseEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private let original: RecurringExpense?

    @State private var title: String
    @State private var amountText: String
    @State private var category: ExpenseCategory
    @State private var paidByMemberID: UUID?
    @State private var splitMethod: Expense.SplitMethod
    @State private var note: String
    @State private var dayOfMonth: Int
    @State private var startMonth: Date
    @State private var hasEndMonth: Bool
    @State private var endMonth: Date
    @State private var isActive: Bool
    @FocusState private var focusedField: Field?

    private enum Field {
        case title
        case amount
        case note
    }

    init(template: RecurringExpense? = nil) {
        original = template
        _title = State(initialValue: template?.title ?? "")
        _amountText = State(initialValue: template.map { String($0.amount) } ?? "")
        _category = State(initialValue: template?.category ?? .utilities)
        _paidByMemberID = State(initialValue: template?.paidByMemberID)
        _splitMethod = State(initialValue: template?.splitMethod ?? .equally)
        _note = State(initialValue: template?.note ?? "")
        _dayOfMonth = State(initialValue: template?.dayOfMonth ?? 25)
        _startMonth = State(initialValue: template?.startMonth ?? .now)
        _hasEndMonth = State(initialValue: template?.endMonth != nil)
        _endMonth = State(initialValue: template?.endMonth ?? .now)
        _isActive = State(initialValue: template?.isActive ?? true)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                contentCard
                scheduleCard
                saveButton
                if original != nil {
                    noticeText
                }
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background)
        .navigationTitle(original == nil ? "定期支出を追加" : "定期支出を編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") { focusedField = nil }
            }
        }
        .onAppear {
            if paidByMemberID == nil {
                paidByMemberID = store.selectedMemberID ?? store.household?.members.first?.id
            }
        }
    }

    private var contentCard: some View {
        VStack(spacing: 17) {
            field("内容") {
                TextField("例：家賃、電気代、動画配信", text: $title)
                    .focused($focusedField, equals: .title)
            }

            field("金額") {
                HStack {
                    Text("¥").foregroundStyle(AppTheme.secondaryText)
                    TextField("0", text: $amountText)
                        .keyboardType(.numberPad)
                        .font(.title3.monospacedDigit().bold())
                        .focused($focusedField, equals: .amount)
                }
            }

            Picker("カテゴリ", selection: $category) {
                ForEach(ExpenseCategory.allCases) { category in
                    Label(category.displayName, systemImage: category.systemImage)
                        .tag(category)
                }
            }

            if let household = store.household {
                Picker("支払う人", selection: $paidByMemberID) {
                    ForEach(household.members) { member in
                        Text(member.displayName).tag(Optional(member.id))
                    }
                }
            }

            Picker("分け方", selection: $splitMethod) {
                ForEach(Expense.SplitMethod.allCases) { method in
                    Text(method.displayName).tag(method)
                }
            }
            .pickerStyle(.segmented)

            field("メモ（任意）") {
                TextField("あとで分かる補足", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($focusedField, equals: .note)
            }
        }
        .appCard()
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            Label("いつ計上するか", systemImage: "calendar.badge.clock")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            Picker("毎月の日", selection: $dayOfMonth) {
                ForEach(RecurringExpense.minimumDayOfMonth...RecurringExpense.maximumDayOfMonth, id: \.self) { day in
                    Text("\(day)日").tag(day)
                }
            }

            Text("31日を選ぶと、2月のように短い月ではその月の最終日に計上します。")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)

            DatePicker("開始月", selection: $startMonth, displayedComponents: .date)
                .datePickerStyle(.compact)

            Toggle("終了月を決める", isOn: $hasEndMonth)
                .tint(AppTheme.positive)

            if hasEndMonth {
                DatePicker("終了月", selection: $endMonth, in: startMonth..., displayedComponents: .date)
                    .datePickerStyle(.compact)
            }

            Text("開始月と終了月は、選んだ日付の「月」だけを見ています。")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)

            Toggle("この定期支出を有効にする", isOn: $isActive)
                .tint(AppTheme.positive)
        }
        .appCard()
    }

    private var saveButton: some View {
        Button(action: save) {
            Text(original == nil ? "定期支出を保存" : "変更を保存")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(.white)
                .background(canSave ? AppTheme.accent : AppTheme.secondaryText.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .disabled(!canSave)
    }

    private var noticeText: some View {
        Text("金額や日を変えても、すでに計上済みの支出はそのまま残ります。過去の分は履歴から編集してください。")
            .font(.footnote)
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var parsedAmount: Int {
        Int(amountText.filter(\.isNumber)) ?? 0
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && parsedAmount > 0
            && paidByMemberID != nil
    }

    private func field<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            content()
                .padding(11)
                .background(AppTheme.background.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func save() {
        guard canSave, let paidByMemberID else { return }
        focusedField = nil
        let template = RecurringExpense(
            id: original?.id ?? UUID(),
            title: title,
            amount: parsedAmount,
            category: category,
            paidByMemberID: paidByMemberID,
            splitMethod: splitMethod,
            note: note,
            dayOfMonth: dayOfMonth,
            startMonth: startMonth,
            endMonth: hasEndMonth ? endMonth : nil,
            isActive: isActive,
            createdAt: original?.createdAt ?? .now,
            updatedAt: .now
        )

        Task {
            if original == nil {
                await store.addRecurringExpense(template)
            } else {
                await store.updateRecurringExpense(template)
            }
            dismiss()
        }
    }
}
