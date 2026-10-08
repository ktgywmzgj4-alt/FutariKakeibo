import SwiftUI

/// 覚えている店の一覧。選ぶ・消す・名前を直すの3つができる。
///
/// **以前はメニューだった。** メニューの行はスワイプできず長押しもできないので、
/// 間違って覚えた店を消すには「いまその店を入力している」必要があり、
/// 一度ずれた名前を直す道が無かった（T-008）。
///
/// - 押す: その店を使う
/// - 横に払う: 忘れる
/// - 長押し: 名前を直す
struct RememberedShopsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    let shops: [MerchantMemo]
    let onPick: (MerchantMemo) -> Void

    /// 名前を直している最中の1件。
    @State private var renaming: MerchantMemo?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Group {
                if shops.isEmpty {
                    ContentUnavailableView(
                        "覚えている店はありません",
                        systemImage: "storefront",
                        description: Text("レシートから保存するときに店名を直すと、次から覚えます。")
                    )
                } else {
                    list
                }
            }
            .background(AppTheme.background)
            .navigationTitle("覚えている店")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .alert("店名を直す", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("店名", text: $newName)
            Button("キャンセル", role: .cancel) { renaming = nil }
            Button("直す") {
                guard let shop = renaming else { return }
                renaming = nil
                Task { await store.renameMerchant(key: shop.key, to: newName) }
            }
        } message: {
            Text("この店を次に読み取ったとき、この名前で入ります。")
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(shops) { shop in
                    row(shop)
                        .listRowBackground(AppTheme.card)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await store.forgetMerchant(key: shop.key) }
                            } label: {
                                Label("忘れる", systemImage: "trash")
                            }
                        }
                }
            } footer: {
                Text("押すと使います。横に払うと忘れ、長押しで名前を直せます。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ shop: MerchantMemo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: shop.category.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(shop.merchant)
                    .font(.body)
                    .foregroundStyle(AppTheme.ink)
                Text(shop.category.displayName)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        // Button ではなくジェスチャで組む。Button に長押しを重ねると、
        // どちらが先に効くかが端末の設定で変わり、押しても何も起きないことがある。
        .contentShape(Rectangle())
        .onTapGesture {
            onPick(shop)
            dismiss()
        }
        .onLongPressGesture {
            newName = shop.merchant
            renaming = shop
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("押すとこの店を使います")
        .accessibilityAction(named: "名前を直す") {
            newName = shop.merchant
            renaming = shop
        }
        .accessibilityAction(named: "忘れる") {
            Task { await store.forgetMerchant(key: shop.key) }
        }
    }
}
