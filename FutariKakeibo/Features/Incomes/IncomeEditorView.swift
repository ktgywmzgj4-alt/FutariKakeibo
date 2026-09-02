import SwiftUI

/// 給与や臨時収入を記録する画面。
struct IncomeEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private let originalIncome: Income?
    private let onSaved: (() -> Void)?

    @State private var title: String
    @State private var amountText: String
    @State private var date: Date
    @State private var source: IncomeSource
    @State private var receivedByMemberID: UUID?
    @State private var note: String
    @State private var showDeleteConfirmation = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case title
        case amount
        case note
    }

    init(income: Income? = nil, onSaved: (() -> Void)? = nil) {
        originalIncome = income
        self.onSaved = onSaved
        _title = State(initialValue: income?.title ?? "")
        _amountText = State(initialValue: income.map { String($0.amount) } ?? "")
        _date = State(initialValue: income?.date ?? .now)
        _source = State(initialValue: income?.source ?? .salary)
        _receivedByMemberID = State(initialValue: income?.receivedByMemberID)
        _note = State(initialValue: income?.note ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                incomeFields

                Button(action: save) {
                    Text(originalIncome == nil ? "収入を保存" : "変更を保存")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundStyle(.white)
                        .background(canSave ? AppTheme.positive : AppTheme.secondaryText.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(!canSave)

                if originalIncome != nil {
                    Button(role: .destructive) { showDeleteConfirmation = true } label: {
                        Text("この収入を削除")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.danger)
                    }
                }
            }
            .padding(18)
        }
        .background(AppTheme.background)
        .navigationTitle(originalIncome == nil ? "収入を追加" : "収入を編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if originalIncome != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") { focusedField = nil }
            }
        }
        .onAppear {
            if receivedByMemberID == nil {
                receivedByMemberID = store.selectedMemberID ?? store.household?.members.first?.id
            }
        }
        .alert("この収入を削除しますか？", isPresented: $showDeleteConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                guard let income = originalIncome else { return }
                Task {
                    await store.deleteIncome(income)
                    dismiss()
                }
            }
        } message: {
            Text("削除後は元に戻せません。共有中の場合はパートナー側からも削除されます。")
        }
    }

    private var incomeFields: some View {
        VStack(spacing: 17) {
            field("内容") {
                TextField("例：8月の給与", text: $title)
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

            DatePicker("日付", selection: $date, displayedComponents: .date)
                .datePickerStyle(.compact)

            Picker("種類", selection: $source) {
                ForEach(IncomeSource.allCases) { source in
                    Label(source.displayName, systemImage: source.systemImage)
                        .tag(source)
                }
            }

            if let household = store.household {
                Picker("受け取った人", selection: $receivedByMemberID) {
                    ForEach(household.members) { member in
                        Text(member.displayName).tag(Optional(member.id))
                    }
                }
            }

            field("メモ（任意）") {
                TextField("あとで分かる補足", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($focusedField, equals: .note)
            }
        }
        .appCard()
    }

    private var parsedAmount: Int {
        Int(amountText.filter(\.isNumber)) ?? 0
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && parsedAmount > 0
            && receivedByMemberID != nil
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
        guard canSave, let receivedByMemberID else { return }
        focusedField = nil
        let income = Income(
            id: originalIncome?.id ?? UUID(),
            title: title,
            amount: parsedAmount,
            date: date,
            source: source,
            receivedByMemberID: receivedByMemberID,
            note: note,
            createdAt: originalIncome?.createdAt ?? .now,
            updatedAt: .now
        )

        Task {
            if originalIncome == nil {
                await store.addIncome(income)
            } else {
                await store.updateIncome(income)
            }

            if let onSaved {
                resetForm()
                onSaved()
            } else {
                dismiss()
            }
        }
    }

    private func resetForm() {
        title = ""
        amountText = ""
        date = .now
        source = .salary
        note = ""
    }
}
