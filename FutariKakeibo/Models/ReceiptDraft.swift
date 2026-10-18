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
    /// 同じ店だと見分けられる鍵の全部（電話番号と、登録番号＋店名）。`MerchantKey.identifiers`。
    ///
    /// 覚えるときはこれを全部覚えておき、次の1枚でどれか1つが読めれば同じ店と分かるようにする。
    var shopIdentifiers: [String]
    /// 同じ事業者だと見分けるための鍵（インボイスの登録番号）。`MerchantKey.businessKey`。
    ///
    /// **支店までは見分けない。** 登録番号は会社ごとの番号で、チェーンの店はみな同じ番号になる。
    var businessKey: String?
    /// 覚えていた店の情報を当てはめたかどうか。画面でそう伝えるために持つ。
    var usedMemo: Bool
    /// 金額を「合計」「お買上」などの語そのものを手がかりに選んだかどうか。
    ///
    /// 立っているときは、端末内のAIの答えで上書きしない。イオンのレシートで
    /// カード会社の番号 47088 が合計になったのは、明細が読めず照合できないまま
    /// AIの答えを通してしまったため。**AIは穴を埋めるだけで、根拠のある答えは動かさない。**
    var amountIsWellEvidenced: Bool
    /// 合計を利用者に確かめてもらうべきかどうか。
    ///
    /// 合計の語も、足し算の裏づけ（小計＋外税、お預り−お釣り、明細の和）も無いとき、
    /// または足し算と食い違うときに立つ。画面で「合計を確かめてください」と伝える。
    var amountNeedsConfirmation: Bool
    /// 確かめてほしい理由。画面にそのまま出す。
    var amountNote: String?
    /// 足し算から見て、合計はこれのはず、という金額（小計＋外税、お預り−お釣り など）。
    ///
    /// 端末の中のAIが合計を答えたとき、ここにある金額と食い違う答えは受け取らない。
    var reconciledTotals: [Int]
    /// 店名を辞書のチェーンから組み立てたか。立っているときは、端末の中のAIの店名で上書きしない。
    var merchantIsWellEvidenced: Bool
    /// 種類を、店（外食など）か品の値段の重さで決めたか。立っているときは、AIの種類で上書きしない。
    var categoryIsWellEvidenced: Bool
    /// 種類を、品の値段の重さで決めたか。立っているときは、覚えた店の種類でも上書きしない
    /// （同じ店でも、買った物で種類は変わる）。
    var categoryDecidedByItems: Bool

    init(
        merchant: String,
        amount: Int? = nil,
        date: Date? = nil,
        items: [ReceiptItem] = [],
        suggestedCategory: ExpenseCategory = .other,
        recognizedText: String = "",
        shopKey: String? = nil,
        shopIdentifiers: [String] = [],
        businessKey: String? = nil,
        usedMemo: Bool = false,
        amountIsWellEvidenced: Bool = false,
        amountNeedsConfirmation: Bool = false,
        amountNote: String? = nil,
        reconciledTotals: [Int] = [],
        merchantIsWellEvidenced: Bool = false,
        categoryIsWellEvidenced: Bool = false,
        categoryDecidedByItems: Bool = false
    ) {
        self.merchant = merchant
        self.amount = amount
        self.date = date
        self.items = items
        self.suggestedCategory = suggestedCategory
        self.recognizedText = recognizedText
        self.shopKey = shopKey
        self.shopIdentifiers = shopIdentifiers
        self.businessKey = businessKey
        self.usedMemo = usedMemo
        self.amountIsWellEvidenced = amountIsWellEvidenced
        self.amountNeedsConfirmation = amountNeedsConfirmation
        self.amountNote = amountNote
        self.reconciledTotals = reconciledTotals
        self.merchantIsWellEvidenced = merchantIsWellEvidenced
        self.categoryIsWellEvidenced = categoryIsWellEvidenced
        self.categoryDecidedByItems = categoryDecidedByItems
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
