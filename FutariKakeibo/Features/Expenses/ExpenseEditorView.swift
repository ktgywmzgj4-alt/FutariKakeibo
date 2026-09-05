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
    @State private var merchant: String
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
    /// 読み取りのあとに残す、保存用の小さな画像。原寸はここには入らない。
    @State private var capturedReceipt: ReceiptImageData?
    /// レシート画像を保存するかどうか。基本はON。人が外せる。
    @State private var shouldSaveReceipt = true
    @State private var isShowingReceipt = false
    @State private var isDeletingReceipt = false
    @State private var validationMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case merchant
        case title
        case amount
        case note
    }

    init(expense: Expense? = nil, onSaved: (() -> Void)? = nil) {
        originalExpense = expense
        self.onSaved = onSaved
        _title = State(initialValue: expense?.title ?? "")
        _merchant = State(initialValue: expense?.merchant ?? "")
        _amountText = State(initialValue: expense.map { String($0.amount) } ?? "")
        _date = State(initialValue: expense?.date ?? .now)
        _category = State(initialValue: expense?.category ?? .groceries)
        _paidByMemberID = State(initialValue: expense?.paidByMemberID)
        _splitMethod = State(initialValue: expense?.splitMethod ?? .equally)
        _note = State(initialValue: expense?.note ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.cardSpacing) {
                receiptCard
                savedReceiptCard
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
            .padding(AppTheme.screenPadding)
        }
        .background(AppTheme.background)
        // 追加タブでは EntryEditorView が大きな見出しを出すので、ここでは空にする。
        .navigationTitle(originalExpense == nil ? "" : "支出を編集")
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
        .sheet(isPresented: $isShowingReceipt) {
            if let expense = storedExpense {
                ReceiptImageViewer(expense: expense)
            }
        }
        .alert("レシート画像を削除しますか？", isPresented: $isDeletingReceipt) {
            Button("キャンセル", role: .cancel) { isDeletingReceipt = false }
            Button("削除", role: .destructive) {
                guard let expense = storedExpense else { return }
                Task { await store.removeReceiptImage(from: expense.id) }
            }
        } message: {
            Text("支出の記録は残ります。共有中の場合は、相手の端末からも見られなくなります。")
        }
    }

    /// 覚えている店の一覧。新しく使ったものが上に来る。
    private var rememberedShops: [MerchantMemo] {
        (store.household?.merchantMemos ?? []).sorted { $0.updatedAt > $1.updatedAt }
    }

    /// いま入力されている店名に対応する、覚えた1件。忘れる操作の対象になる。
    private var matchedShop: MerchantMemo? {
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return rememberedShops.first { $0.merchant == name }
    }

    /// 覚えた店から選ぶ、または間違って覚えた店を忘れる。
    @ViewBuilder
    private var shopMenu: some View {
        if !rememberedShops.isEmpty {
            Menu {
                Section("覚えている店") {
                    ForEach(rememberedShops) { shop in
                        Button {
                            merchant = shop.merchant
                            category = shop.category
                        } label: {
                            Label(shop.merchant, systemImage: shop.category.systemImage)
                        }
                    }
                }
                if let matchedShop {
                    Section {
                        Button(role: .destructive) {
                            Task { await store.forgetMerchant(key: matchedShop.key) }
                        } label: {
                            Label("「\(matchedShop.merchant)」を忘れる", systemImage: "trash")
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("覚えている店から選ぶ")
        }
    }

    /// 保存する名前。内容が空なら店名を使う。
    /// レシートを読んだ直後は内容が空なので、そのまま保存できるようにしておく。
    private var effectiveTitle: String {
        let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? merchant.trimmingCharacters(in: .whitespacesAndNewlines) : typed
    }

    private var canSave: Bool {
        !effectiveTitle.isEmpty
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
                    if isRecognizing {
                        ProgressView().tint(AppTheme.accent)
                    } else {
                        Image(systemName: "doc.viewfinder")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text(isRecognizing ? "レシートを読み取り中…" : "レシートから入力")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    // 実装の実態に合わせた文言。文字の読み取りは端末の中で終わる。
                    // 画像を残すかどうかは、読み取ったあとに下のスイッチで選ぶ。
                    Text("読み取りはこのiPhone内だけで行います")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer(minLength: 0)
            }

            Divider().overlay(AppTheme.line)

            // カメラとアルバムは同じ大きさで横に並べる。
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

                Divider().frame(height: 56).overlay(AppTheme.line)

                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    sourceLabel(title: "アルバム", caption: "写真を選択する", systemImage: "photo.fill")
                }
                .buttonStyle(.plain)
                .disabled(isRecognizing)
                .accessibilityHint("保存済みの写真からレシートを選びます")
            }

            if capturedReceipt != nil {
                Divider().overlay(AppTheme.line)
                receiptSaveToggle
            }
        }
        .appCard()
    }

    /// 読み取ったレシートの画像を残すかどうか。基本はON。
    ///
    /// ここに来る画像はすでに縮小・圧縮済みで、原寸ではない。
    @ViewBuilder
    private var receiptSaveToggle: some View {
        if let capturedReceipt {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $shouldSaveReceipt) {
                    Text("レシート画像を保存")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                }
                .tint(AppTheme.accent)

                Text(receiptSaveCaption(for: capturedReceipt))
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func receiptSaveCaption(for image: ReceiptImageData) -> String {
        guard shouldSaveReceipt else {
            return "保存しません。読み取った内容だけが記録されます。"
        }
        let size = Int64(image.byteCount).formatted(.byteCount(style: .file))
        return "あとで見返せるよう、縮小した1枚（およそ\(size)）を保存します。"
            + "共有中は相手も同じレシートを見られます。"
    }

    /// 保存済みのレシート。この画面は支出の詳細も兼ねているので、ここから見られるようにする。
    @ViewBuilder
    private var savedReceiptCard: some View {
        if let expense = storedExpense, expense.hasReceiptImage {
            VStack(alignment: .leading, spacing: 12) {
                Label("レシート", systemImage: "doc.text.image")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                Text("この支出にはレシート画像が付いています。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)

                HStack(spacing: 10) {
                    Button {
                        isShowingReceipt = true
                    } label: {
                        Label("レシートを見る", systemImage: "eye")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(AppTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        isDeletingReceipt = true
                    } label: {
                        Label("削除", systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .foregroundStyle(AppTheme.danger)
                            .background(AppTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(AppTheme.line, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .appCard()
        }
    }

    /// いま編集している支出の、保存されている姿。レシートを消した直後もここに反映される。
    private var storedExpense: Expense? {
        guard let originalExpense else { return nil }
        return store.expenses.first { $0.id == originalExpense.id } ?? originalExpense
    }

    private func sourceLabel(title: String, caption: String, systemImage: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(height: 40)
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
            field("店名") {
                HStack(spacing: 10) {
                    TextField("例：Selfix北名古屋", text: $merchant)
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .merchant)
                    shopMenu
                }
            }

            field("内容") {
                TextField("例：ガソリン", text: $title)
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
                        // 支払った人にも、その人の識別色を使う。
                        Label {
                            Text(member.displayName)
                        } icon: {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundStyle(household.color(of: member.id))
                        }
                        .tag(Optional(member.id))
                    }
                }
            }

            // 折半か個人か。選ばれているほうを白地にブルーの枠と文字で示す。
            HStack(spacing: 10) {
                ForEach(Expense.SplitMethod.allCases) { method in
                    Button {
                        splitMethod = method
                    } label: {
                        Text(method.displayName)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(splitMethod == method ? AppTheme.accent : AppTheme.secondaryText)
                            .background(splitMethod == method ? AppTheme.card : AppTheme.accentSoft.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        splitMethod == method ? AppTheme.accent : AppTheme.line,
                                        lineWidth: splitMethod == method ? 1.5 : 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(splitMethod == method ? [.isSelected, .isButton] : .isButton)
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
                // 読み取りは済んだ。保存するのはここで作る縮小した1枚だけで、
                // 原寸の画像はこの処理を抜けたら誰も持たない。
                if let original = images.first {
                    capturedReceipt = await ReceiptImageProcessor.process(image: original)
                    shouldSaveReceipt = true
                }
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
                if !remembered.merchant.isEmpty { merchant = remembered.merchant }
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
            title: effectiveTitle,
            amount: parsedAmount,
            date: date,
            category: category,
            paidByMemberID: paidByMemberID,
            splitMethod: splitMethod,
            note: note,
            merchant: merchant,
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
                    key: shopKey,
                    merchant: expense.merchant ?? expense.title,
                    category: expense.category
                )
            }

            // レシート画像は支出とは別に保存する。支出データに入るのは参照だけ。
            if shouldSaveReceipt, let capturedReceipt {
                await store.attachReceiptImage(capturedReceipt, to: expense.id)
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
        merchant = ""
        amountText = ""
        date = .now
        category = .groceries
        splitMethod = .equally
        note = ""
        recognizedText = ""
        detectedItems = []
        shopKey = nil
        capturedReceipt = nil
        shouldSaveReceipt = true
    }
}
