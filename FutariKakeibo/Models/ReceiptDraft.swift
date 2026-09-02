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

    init(
        merchant: String,
        amount: Int? = nil,
        date: Date? = nil,
        items: [ReceiptItem] = [],
        suggestedCategory: ExpenseCategory = .other,
        recognizedText: String = ""
    ) {
        self.merchant = merchant
        self.amount = amount
        self.date = date
        self.items = items
        self.suggestedCategory = suggestedCategory
        self.recognizedText = recognizedText
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
