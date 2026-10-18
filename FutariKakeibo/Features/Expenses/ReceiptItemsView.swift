import SwiftUI

/// 読み取った品の一覧。品の名前と種類を直せる。
///
/// **直した品だけ**、この店での品の書き方と、直した名前・種類を覚える（`ItemNote`、
/// 2026-10-18 利用者が決定）。金額は出さない。明細は記録しないので、記録されるように見せない。
struct ReceiptItemsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var items: [ReceiptItem]
    /// 人が直した品の番号。保存のときに、これだけを覚える。
    @Binding var edited: Set<Int>

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items.indices, id: \.self) { index in
                        row(index)
                            .listRowBackground(AppTheme.card)
                    }
                } footer: {
                    Text("直した品だけ、この店での品の書き方と、直した名前・種類を覚えます。"
                        + "次に同じ店のレシートを読むと、最初からそうなります。金額と日付は残しません。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("読み取った品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func row(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 読み取った書き方。覚えるのはこの書き方。
            Text(items[index].name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            TextField("正しい名前（分かれば）", text: name(at: index))
                .font(.subheadline)
            Picker("種類", selection: category(at: index)) {
                Text("分からない").tag(ExpenseCategory?.none)
                ForEach(ExpenseCategory.allCases) { category in
                    Label(category.displayName, systemImage: category.systemImage)
                        .tag(ExpenseCategory?.some(category))
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }

    /// 名前の入力。前後の空白は保存のときに落とす（打っている途中の空白を消さないため）。
    private func name(at index: Int) -> Binding<String> {
        Binding(
            get: { items.indices.contains(index) ? (items[index].normalizedName ?? "") : "" },
            set: { value in
                guard items.indices.contains(index) else { return }
                items[index].normalizedName = value.isEmpty ? nil : value
                edited.insert(index)
            }
        )
    }

    private func category(at index: Int) -> Binding<ExpenseCategory?> {
        Binding(
            get: { items.indices.contains(index) ? items[index].category : nil },
            set: { value in
                guard items.indices.contains(index) else { return }
                items[index].category = value
                edited.insert(index)
            }
        )
    }
}

/// ある店で覚えた品の一覧。横に払うと忘れる。
///
/// 間違って直した品を、もう一度同じ店のレシートを撮らなくても消せるように。
struct RememberedItemsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    let shopKey: String
    let shopName: String

    /// 消したらすぐ一覧から消えるように、覚えた店は毎回ストアから読む。
    private var notes: [ItemNote] {
        store.household?.merchantMemos.first { $0.key == shopKey }?.itemNotes ?? []
    }

    var body: some View {
        NavigationStack {
            Group {
                if notes.isEmpty {
                    ContentUnavailableView(
                        "覚えた品はありません",
                        systemImage: "list.bullet",
                        description: Text("レシートから保存するときに品の名前や種類を直すと、ここに出ます。")
                    )
                } else {
                    List {
                        Section {
                            ForEach(notes, id: \.key) { note in
                                row(note)
                                    .listRowBackground(AppTheme.card)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            forget(note)
                                        } label: {
                                            Label("忘れる", systemImage: "trash")
                                        }
                                    }
                            }
                        } footer: {
                            Text("横に払うと忘れます。次に同じ書き方の品を読んだときは、辞書の読み方に戻ります。")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AppTheme.background)
            .navigationTitle(shopName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func row(_ note: ItemNote) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.text)
                .font(.body)
                .foregroundStyle(AppTheme.ink)
            Text([note.name, note.category?.displayName].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "忘れる") { forget(note) }
    }

    private func forget(_ note: ItemNote) {
        Task { await store.forgetItemNote(shopKey: shopKey, noteKey: note.key) }
    }
}
