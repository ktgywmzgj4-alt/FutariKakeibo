import SwiftUI
import PhotosUI
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
    @State private var photoItem: PhotosPickerItem?
    @State private var detectedItems: [ReceiptItem] = []
    /// レシートから読み取ったときの店の鍵。保存できたらこの店を覚える。
    @State private var shopKey: String?
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
                receiptCard
                detectedItemsCard
                expenseFields

                Button(action: save) {
                    Text(originalExpense == nil ? "支出を保存" : "変更を保存")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundStyle(.white)
                        .background(canSave ? AppTheme.accent : AppTheme.secondaryText.opacity(0.4))
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
                    .foregroundStyle(AppTheme.ink)
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
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            photoItem = nil
            Task { @MainActor in
                guard
                    let data = try? await newItem.loadTransferable(type: Data.self),
                    let image = UIImage(data: data)
                else {
                    validationMessage = "写真を読み込めませんでした。別の写真を選んでください。"
                    return
                }
                recognize([image])
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

    private var receiptCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accentSoft.opacity(0.45))
                        .frame(width: 52, height: 52)
                    if isRecognizing {
                        ProgressView().tint(AppTheme.accent)
                    } else {
                        Image(systemName: "doc.viewfinder.fill")
                            .font(.title2)
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(isRecognizing ? "レシートを読み取り中…" : "レシートから入力")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text("画像は保存・送信せず、このiPhone内で処理します")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 0) {
                Button {
                    isShowingScanner = true
                } label: {
                    sourceLabel(title: "カメラ", caption: "その場で撮影する", systemImage: "camera.fill")
                }
                .buttonStyle(.plain)
                .disabled(!VNDocumentCameraViewController.isSupported || isRecognizing)
                .opacity(VNDocumentCameraViewController.isSupported ? 1 : 0.45)
                .accessibilityHint("カメラでレシートを撮影します")

                Divider().frame(height: 62)

                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    sourceLabel(title: "アルバム", caption: "写真を選択する", systemImage: "photo.fill")
                }
                .buttonStyle(.plain)
                .disabled(isRecognizing)
                .accessibilityHint("保存済みの写真からレシートを選びます")
            }
            .background(AppTheme.background.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.accentSoft.opacity(0.75), lineWidth: 1)
            )
        }
        .appCard()
    }

    private func sourceLabel(title: String, caption: String, systemImage: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 44, height: 44)
                .background(AppTheme.accentSoft.opacity(0.35))
                .clipShape(Circle())
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.ink)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var detectedItemsCard: some View {
        if !detectedItems.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                Label("種類を推測した手がかり", systemImage: "list.bullet.rectangle.portrait")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                // 明細は記録しない。何を買ったかから支出の種類を推測するためだけに使う。
                // 金額を並べると「これも記録される」と読めてしまうので出さない。
                Text(detectedItems.map(\.name).joined(separator: "・"))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text("レシートから読み取った品名です。記録されるのは日付・店名・合計金額・種類の4つだけです。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .appCard()
        }
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
                let lines = try await ReceiptRecognizer.recognize(images: images)
                // 端末の中のAIが使えるならAIに、使えなければルールに読ませる。
                // どちらの場合も、文字は端末の外へ出ない。
                let draft = await ReceiptInterpreter.interpret(lines: lines)
                // 覚えている店なら、読み取りの推測より人が直した結果を優先する。
                let remembered = MerchantMemory.applying(
                    store.household?.merchantMemos ?? [], to: draft
                )
                recognizedText = remembered.recognizedText
                detectedItems = remembered.items
                shopKey = remembered.shopKey
                if !remembered.merchant.isEmpty { title = remembered.merchant }
                if let amount = remembered.amount { amountText = String(amount) }
                if let receiptDate = remembered.date { date = receiptDate }
                category = remembered.suggestedCategory
                validationMessage = readBackMessage(for: remembered)
            } catch {
                validationMessage = error.localizedDescription
            }
        }
    }

    /// 何が読み取れて何が読み取れなかったかを、保存前にはっきり伝える。
    private func readBackMessage(for draft: ReceiptDraft) -> String {
        var known: [String] = []
        var missing: [String] = []
        if draft.merchant.isEmpty { missing.append("店名") } else { known.append("店名") }
        if draft.amount == nil { missing.append("金額") } else { known.append("金額") }
        if draft.date == nil { missing.append("日付") } else { known.append("日付") }

        if missing.isEmpty {
            return "店名・日付・金額を読み取りました。保存前に内容を確認してください。"
        }
        if known.isEmpty {
            return "うまく読み取れませんでした。明るい場所でレシート全体が入るように撮り直すか、手入力で保存してください。"
        }
        return "\(known.joined(separator: "・"))を読み取りました。\(missing.joined(separator: "・"))は読み取れなかったので入力してください。"
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

            // レシートから読み取った支出なら、保存できた形でこの店を覚える。
            // 人が直したあとの値なので、次に同じ店を読んだときはこれが出る。
            if let shopKey {
                await store.rememberMerchant(
                    key: shopKey, merchant: expense.title, category: expense.category
                )
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
        detectedItems = []
        shopKey = nil
    }
}
