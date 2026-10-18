import Foundation

/// 品ごとの種類と、レシート全体の種類。
///
/// **店名だけで種類を決めない。** ドラッグストアで食べ物を買うこともあるし、
/// スーパーで洗剤だけ買うこともある。品ごとに種類を見て、値段の重さで全体を決める。
/// ただし飲食店やガソリンスタンドのように、店で決まる種類は店を優先する
/// （外食の品は「ロコモコ」「アイスコーヒー」のように、スーパーにもある名前ばかり）。
///
/// 支出に記録する種類は1つのまま（データの形は変えない）。品ごとの内訳は読み取りの中だけで使う。
extension ReceiptParser {
    /// 店で決まる種類。品の内訳で上書きしない。
    private static let shopDecidedCategories: Set<ExpenseCategory> = [
        .dining, .transportation, .utilities, .travel, .entertainment
    ]

    /// 品の種類を足し上げたときに、全体の種類として採るための割合。
    /// 種類の分かった品の値段が、明細の和のこれ以上を占めていること。
    private static let weightedCategoryShare = 0.5

    /// 品ごとに、種類と、略し方から分かる正式な名前を付ける。
    ///
    /// 正式な名前は**辞書にある略し方だけ**。分からない略し方は読み取ったままにする
    /// （もっともらしい名前を作らない）。
    static func annotated(_ items: [ReceiptItem], dictionary: ReceiptDictionary) -> [ReceiptItem] {
        items.map { item in
            var annotated = item
            let key = Array(dictionaryKey(item.name).unicodeScalars)
            if let product = dictionary.productNames.first(where: { entry in
                entry.keyScalars.contains { exactSpan(of: $0, in: key) != nil }
            }) {
                annotated.normalizedName = product.name
            }
            var keys = [key]
            if let normalized = annotated.normalizedName {
                keys.append(Array(dictionaryKey(normalized).unicodeScalars))
            }
            annotated.category = dictionary.productCategories.first { entry in
                entry.keyScalars.contains { word in keys.contains { exactSpan(of: word, in: $0) != nil } }
            }?.category
            return annotated
        }
    }

    /// 品の種類を値段の重さで足し上げ、いちばん重い種類。決めきれなければ nil。
    static func weightedCategory(of items: [ReceiptItem]) -> ExpenseCategory? {
        let total = items.reduce(0) { $0 + max($1.netAmount, 0) }
        guard total > 0 else { return nil }
        var weights: [ExpenseCategory: Int] = [:]
        for item in items {
            guard let category = item.category else { continue }
            weights[category, default: 0] += max(item.netAmount, 0)
        }
        let known = weights.values.reduce(0, +)
        guard known > 0, Double(known) >= Double(total) * weightedCategoryShare else { return nil }
        // 同じ重さなら、並びの先（外食 → 食費 → 日用品 → 医療 → 美容）。毎回同じ答えにするため。
        var best: (category: ExpenseCategory, weight: Int)?
        for category in [ExpenseCategory.dining, .groceries, .household, .health, .beauty] {
            guard let weight = weights[category] else { continue }
            if weight > (best?.weight ?? 0) { best = (category, weight) }
        }
        return best?.category
    }

    /// レシート全体の種類と、それが確かな手がかりで決まったか、品の値段の重さで決まったか。
    ///
    /// 1. 店で決まる種類（外食・交通など）は店を優先する
    /// 2. 品の種類を値段の重さで足し上げて決まれば、それ
    /// 3. 店（チェーン）の種類
    /// 4. それも無ければ、これまでの決め方（店名 → 品名 → 全文の語）
    static func receiptCategory(
        text: String,
        merchant: String,
        items: [ReceiptItem],
        chain: ReceiptDictionary.Chain?
    ) -> (category: ExpenseCategory, wellEvidenced: Bool, byItems: Bool) {
        let fromShop = chain?.category ?? bestMatch(in: merchant)
        if let fromShop, shopDecidedCategories.contains(fromShop) {
            return (fromShop, true, false)
        }
        if let weighted = weightedCategory(of: items) {
            return (weighted, true, true)
        }
        if let chain {
            return (chain.category, true, false)
        }
        return (category(from: text, merchant: merchant, items: items), false, false)
    }
}
