import Foundation

struct ReceiptDraft: Equatable, Sendable {
    /// どこで買ったか。
    var merchant: String
    /// いくら払ったか。
    var amount: Int?
    /// いつ買ったか。
    var date: Date?
    /// 何を買ったか。読み取れた明細。
    var items: [ReceiptItem]
    var suggestedCategory: ExpenseCategory
    var recognizedText: String
    /// 同じ店だと見分けるための鍵。覚えた店を引き当てるのに使う（`MerchantKey`）。
    var shopKey: String?
    /// 覚えていた店の情報を当てはめたかどうか。画面でそう伝えるために持つ。
    var usedMemo: Bool
    /// 金額を「合計」「お買上」などの語そのものを手がかりに選んだかどうか。
    ///
    /// 立っているときは、端末内のAIの答えで上書きしない。イオンのレシートで
    /// カード会社の番号 47088 が合計になったのは、明細が読めず照合できないまま
    /// AIの答えを通してしまったため。**AIは穴を埋めるだけで、根拠のある答えは動かさない。**
    var amountIsWellEvidenced: Bool

    init(
        merchant: String,
        amount: Int? = nil,
        date: Date? = nil,
        items: [ReceiptItem] = [],
        suggestedCategory: ExpenseCategory = .other,
        recognizedText: String = "",
        shopKey: String? = nil,
        usedMemo: Bool = false,
        amountIsWellEvidenced: Bool = false
    ) {
        self.merchant = merchant
        self.amount = amount
        self.date = date
        self.items = items
        self.suggestedCategory = suggestedCategory
        self.recognizedText = recognizedText
        self.shopKey = shopKey
        self.usedMemo = usedMemo
        self.amountIsWellEvidenced = amountIsWellEvidenced
    }

    static let empty = ReceiptDraft(merchant: "")

    /// 読み取れた内容を1行にまとめた、保存前の確認用の説明。
    var summary: String {
        var parts: [String] = []
        if !merchant.isEmpty { parts.append(merchant) }
        if let amount { parts.append(amount.yenText) }
        if !items.isEmpty { parts.append("明細\(items.count)件") }
        return parts.joined(separator: " · ")
    }
}
