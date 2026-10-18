import SwiftUI

/// 覚えている店の一覧。選ぶ・消す・名前を直すの3つができる。
///
/// **以前はメニューだった。** メニューの行はスワイプできず長押しもできないので、
/// 間違って覚えた店を消すには「いまその店を入力している」必要があり、
/// 一度ずれた名前を直す道が無かった（T-008）。
///
/// - 押す: その店を使う
/// - 左へ払う: 忘れる
/// - 右へ払う: その店で覚えた品を見る・消す
/// - 長押し: 名前を直す
struct RememberedShopsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    let shops: [MerchantMemo]
    let onPick: (MerchantMemo) -> Void

    /// 名前を直している最中の1件。
    @State private var renaming: MerchantMemo?
    @State private var newName = ""
    /// 覚えた品を見ている店。
    @State private var itemsShop: MerchantMemo?

    var body: some View {
        NavigationStack {
            Group {
                if shops.isEmpty {
                    ContentUnavailableView(
                        "覚えている店はありません",
                        systemImage: "storefront",
                        description: Text("レシートから保存すると、その店を覚えます。店名や種類を直して保存した店は、次から最初にその内容が出ます。")
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
        .sheet(item: $itemsShop) { shop in
            RememberedItemsView(shopKey: shop.key, shopName: shop.merchant)
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
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if !(shop.itemNotes ?? []).isEmpty {
                                Button {
                                    itemsShop = shop
                                } label: {
                                    Label("覚えた品", systemImage: "list.bullet")
                                }
                                .tint(AppTheme.accent)
                            }
                        }
                }
            } footer: {
                Text("押すと使います。左へ払うと忘れ、長押しで名前を直せます。"
                    + "品を覚えている店は、右へ払うと覚えた品を見て消せます。\n"
                    + "直して保存した店と、同じ内容で2回保存した店は、次から読み取りより優先します。"
                    + "「1回だけ」の店は、読み取れなかったところだけを埋めます。")
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
                // 直さずに1回保存しただけの店は、まだ読み取りより優先しない。そのことを添える。
                Text(caption(for: shop))
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
        .accessibilityAction(named: "覚えた品") {
            itemsShop = shop
        }
    }

    /// 種類と、まだ確かでないこと、覚えた品の数。
    private func caption(for shop: MerchantMemo) -> String {
        var parts = [shop.category.displayName]
        if !shop.isTrusted { parts.append("1回だけ") }
        if let count = shop.itemNotes?.count, count > 0 { parts.append("品 \(count)件") }
        return parts.joined(separator: " · ")
    }
}
