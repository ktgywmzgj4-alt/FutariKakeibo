import SwiftUI
import UIKit
import VisionKit

struct ExpenseEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private let originalExpense: Expense?
    private let onSaved: (() -> Void)?

    @State private var title: String
    @State private var amountText: String
    @State private var date: Date
    @State private var category: ExpenseCategory
    @State private var paidByMemberID: UUID?
    @State private var splitMethod: Expense.SplitMethod
    @State private var note: String
    @State private var isShowingScanner = false
    @State private var isRecognizing = false
    @State private var recognizedText = ""
    @State private var validationMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case title
        case amount
        case note
    }

    init(expense: Expense? = nil, onSaved: (() -> Void)? = nil) {
        originalExpense = expense
        self.onSaved = onSaved
        _title = State(initialValue: expense?.title ?? "")
        _amountText = State(initialValue: expense.map { String($0.amount) } ?? "")
        _date = State(initialValue: expense?.date ?? .now)
        _category = State(initialValue: expense?.category ?? .groceries)
        _paidByMemberID = State(initialValue: expense?.paidByMemberID)
        _splitMethod = State(initialValue: expense?.splitMethod ?? .equally)
        _note = State(initialValue: expense?.note ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                receiptButton
                expenseFields

                Button(action: save) {
                    Text(originalExpense == nil ? "支出を保存" : "変更を保存")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundStyle(.white)
                        .background(canSave ? AppTheme.terracotta : AppTheme.secondaryText.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(!canSave)

                if !recognizedText.isEmpty {
                    DisclosureGroup("読み取った文字を確認") {
                        Text(recognizedText)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppTheme.secondaryText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                    .font(.footnote)
                    .foregroundStyle(AppTheme.deepGreen)
                    .appCard()
                }
            }
            .padding(18)
        }
        .background(AppTheme.background)
        .navigationTitle(originalExpense == nil ? "支出を追加" : "支出を編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if originalExpense != nil {
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
            if paidByMemberID == nil {
                paidByMemberID = store.selectedMemberID ?? store.household?.members.first?.id
            }
        }
        .sheet(isPresented: $isShowingScanner) {
            ReceiptScannerView(onCancel: {
                isShowingScanner = false
            }) { result in
                isShowingScanner = false
                switch result {
                case let .success(images): recognize(images)
                case let .failure(error): validationMessage = error.localizedDescription
                }
            }
            .ignoresSafeArea()
        }
        .alert("確認してください", isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button("閉じる", role: .cancel) { validationMessage = nil }
        } message: {
            Text(validationMessage ?? "")
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && parsedAmount > 0
            && paidByMemberID != nil
            && !isRecognizing
    }

    private var parsedAmount: Int {
        Int(amountText.filter(\.isNumber)) ?? 0
    }

    private var receiptButton: some View {
        Button {
            isShowingScanner = true
        } label: {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(AppTheme.terracottaSoft.opacity(0.45))
                        .frame(width: 48, height: 48)
                    if isRecognizing {
                        ProgressView().tint(AppTheme.terracotta)
                    } else {
                        Image(systemName: "doc.viewfinder.fill")
                            .font(.title2)
                            .foregroundStyle(AppTheme.terracotta)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(isRecognizing ? "レシートを読み取り中…" : "レシートから入力")
                        .font(.headline)
                    Text("画像は保存・送信せず、このiPhone内で処理します")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .foregroundStyle(AppTheme.deepGreen)
        }
        .buttonStyle(.plain)
        .disabled(!VNDocumentCameraViewController.isSupported || isRecognizing)
        .opacity(VNDocumentCameraViewController.isSupported ? 1 : 0.55)
        .appCard()
        .accessibilityHint("カメラでレシートを撮影します")
    }

    private var expenseFields: some View {
        VStack(spacing: 17) {
            field("内容") {
                TextField("例：スーパーで食材", text: $title)
                    .textInputAutocapitalization(.never)
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

            Picker("カテゴリ", selection: $category) {
                ForEach(ExpenseCategory.allCases) { category in
                    Label(category.displayName, systemImage: category.systemImage)
                        .tag(category)
                }
            }

            if let household = store.household {
                Picker("支払った人", selection: $paidByMemberID) {
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

    private func recognize(_ images: [UIImage]) {
        guard !images.isEmpty else {
            validationMessage = "レシートを読み取れませんでした。もう一度撮影してください。"
            return
        }
        isRecognizing = true
        // OCRはバックグラウンドで実行されるため、結果の反映は明示的にメインアクターへ戻して行う。
        Task { @MainActor in
            defer { isRecognizing = false }
            do {
                let text = try await ReceiptRecognizer.recognize(images: images)
                let draft = ReceiptParser.parse(text: text)
                recognizedText = text
                if !draft.merchant.isEmpty { title = draft.merchant }
                if let amount = draft.amount { amountText = String(amount) }
                if let receiptDate = draft.date { date = receiptDate }
                category = draft.suggestedCategory
                validationMessage = "候補を入力しました。金額や店名が正しいか、保存前に確認してください。"
            } catch {
                validationMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        guard canSave, let paidByMemberID else { return }
        focusedField = nil
        let expense = Expense(
            id: originalExpense?.id ?? UUID(),
            title: title,
            amount: parsedAmount,
            date: date,
            category: category,
            paidByMemberID: paidByMemberID,
            splitMethod: splitMethod,
            note: note,
            createdAt: originalExpense?.createdAt ?? .now,
            updatedAt: .now
        )

        Task {
            if originalExpense == nil {
                await store.addExpense(expense)
            } else {
                await store.updateExpense(expense)
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
        category = .groceries
        splitMethod = .equally
        note = ""
        recognizedText = ""
    }
}
