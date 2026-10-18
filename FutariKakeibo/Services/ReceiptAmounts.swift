import Foundation

/// 合計を、レシートに刷られたほかの数字から確かめる。
///
/// 合計は「合計」の語だけを頼りにすると外れる。語が読めないことがあり（コノミヤ）、
/// カード会社の番号や伝票番号のような、金額と同じ形の数字も多い（イオンの 47088）。
/// レシートには**同じ金額を別の道筋で確かめられる数字**が刷られている。
///
/// - 外税: 小計 ＋ 外税 ＝ 合計
/// - 現金: お預り − お釣り ＝ 合計
/// - 明細: 品の値段 − 値引き（＋ 外税）＝ 合計
/// - 内税: 合計に含まれる消費税（合計 × 税率 ÷（1 ＋ 税率））＝ 内消費税
///
/// 確かめられた候補に点を足し、どの道筋とも食い違うときは利用者に確かめてもらう。
///
/// **品の値段は変えない。** つじつまを合わせるために数字を作ることはしない。
/// 読み取りの別の読み方（`RecognizedLine.alternatives`）から選び直すのは、
/// そちらで足し算が合うときだけ（`ReceiptParser.totalCandidates`）。
extension ReceiptParser {
    /// 合計を確かめるための、レシートの下のほうの数字。
    struct Summary: Equatable, Sendable {
        /// 小計。
        var subtotal: Int?
        /// 外税の額。「外税計」の行があればその値、無ければ率ごとの行（外税 8%・外税10%）を足したもの。
        var outerTax: Int?
        /// 内税の額（「内消費税等」「うち消費税」）。
        var innerTax: Int?
        /// お預り（現金で渡した額）。
        var tendered: Int?
        /// お釣り。
        var change: Int?
        /// クレジット・電子マネーなど、現金以外で払った額。
        var payments: [Int] = []
    }

    /// 選んだ合計を、足し算で確かめた結果。
    struct AmountCheck: Equatable, Sendable {
        /// 足し算から見て、合計はこれのはず、という金額。
        var reconciledTotals: [Int] = []
        /// 選んだ合計が足し算と食い違う。
        var conflicts = false
        /// 利用者に確かめてもらう。食い違うとき、または合計の語も足し算の裏づけも無いとき。
        var needsConfirmation = false
        /// 画面に出す理由。
        var note: String?
    }

    // MARK: - 拾う語

    private static let subtotalKeywords = ["小計"]
    /// 外税の合計。
    private static let outerTaxTotalKeywords = ["外税計", "外税合計"]
    /// 「税合計」は外税のレシートでだけ外税として使う。内税のレシートでは含まれる税の額のことがある。
    private static let taxTotalKeywords = ["税合計"]
    private static let innerTaxKeywords = ["内消費税", "内税", "うち消費税"]
    /// 税率ごとの「対象額」。税の額ではない。
    private static let taxableKeywords = ["対象", "タイショウ"]
    private static let tenderedKeywords = ["お預り", "お預かり", "預り", "預かり", "現金"]
    private static let changeKeywords = ["お釣", "おつり", "釣銭", "お返し"]
    private static let paymentKeywords = [
        "クレジット", "電子マネー", "交通系", "quicpay", "paypay", "waon", "nanaco",
        "suica", "pasmo", "楽天ペイ", "d払い", "aupay", "au pay", "メルペイ", "edy"
    ]
    /// 支払いの欄に見えるが、払った額ではない行（売上票の見出し、カード会社の番号）。
    private static let notPaymentKeywords = ["売上票", "カード会社", "会員番号", "伝票", "承認", "残高"]

    // MARK: - 拾う

    static func summary(of rows: [Row]) -> Summary {
        var summary = Summary()
        var perRateOuterTax: [Int] = []
        var outerTaxTotal: Int?
        var taxTotal: Int?
        var sawOuterTax = false

        for index in rows.indices {
            let text = rows[index].text
            let taxable = containsKeyword(text, from: taxableKeywords)
            if containsKeyword(text, from: outerTaxTotalKeywords) {
                sawOuterTax = true
                if outerTaxTotal == nil { outerTaxTotal = labelledAmount(at: index, in: rows) }
            } else if containsKeyword(text, from: taxTotalKeywords) {
                if !taxable, taxTotal == nil { taxTotal = labelledAmount(at: index, in: rows) }
            } else if isOuterTaxRateRow(text) {
                sawOuterTax = true
                if !taxable, let value = labelledAmount(at: index, in: rows) {
                    perRateOuterTax.append(value)
                }
            } else if containsKeyword(text, from: innerTaxKeywords) {
                if !taxable, summary.innerTax == nil {
                    summary.innerTax = labelledAmount(at: index, in: rows)
                }
            } else if containsKeyword(text, from: subtotalKeywords) {
                if summary.subtotal == nil { summary.subtotal = labelledAmount(at: index, in: rows) }
            } else if containsKeyword(text, from: changeKeywords) {
                if summary.change == nil {
                    summary.change = labelledAmount(at: index, in: rows, allowingZero: true)
                }
            } else if containsKeyword(text, from: tenderedKeywords) {
                if summary.tendered == nil { summary.tendered = labelledAmount(at: index, in: rows) }
            } else if containsKeyword(text, from: paymentKeywords),
                      !containsKeyword(text, from: notPaymentKeywords),
                      let value = labelledAmount(at: index, in: rows) {
                summary.payments.append(value)
            }
        }

        if let outerTaxTotal {
            summary.outerTax = outerTaxTotal
        } else if sawOuterTax, let taxTotal {
            summary.outerTax = taxTotal
        } else if !perRateOuterTax.isEmpty {
            summary.outerTax = perRateOuterTax.reduce(0, +)
        }
        return summary
    }

    /// 外税の行（「外税 8%」「外税額 10%」「外8%」）。対象額の行も含む。
    private static func isOuterTaxRateRow(_ text: String) -> Bool {
        if containsKeyword(text, from: ["外税"]) { return true }
        return matches(#"外\s*[0-9]{1,2}\s*[%％]"#, in: normalizedDigits(text))
    }

    /// その行の金額。行に無ければ、すぐ下が金額だけの行ならそれを使う
    /// （「クレジット」の下の行に「¥5,302」が来る読まれ方がある）。
    private static func labelledAmount(at index: Int, in rows: [Row], allowingZero: Bool = false) -> Int? {
        if let value = rowAmount(rows[index].text, allowingZero: allowingZero) { return value }
        let next = index + 1
        guard next < rows.count, isAmountOnlyRow(rows[next].text) else { return nil }
        return rowAmount(rows[next].text, allowingZero: allowingZero)
    }

    /// 行の右端の金額。通貨の印が付いたものを先に見る。
    private static func rowAmount(_ text: String, allowingZero: Bool) -> Int? {
        let accepts: (Int) -> Bool = { value in
            allowingZero ? (0...9_999_999).contains(value) : isPlausibleAmount(value)
        }
        if let marked = currencyAmounts(in: text).filter(accepts).last { return marked }
        return amounts(in: text).filter(accepts).last
    }

    /// 金額と、点数のような短い添え書きだけの行（「¥5,302」「4点 ¥884」）。
    static func isAmountOnlyRow(_ text: String) -> Bool {
        guard !currencyAmounts(in: text).isEmpty || !amounts(in: text).isEmpty else { return false }
        return !text.contains { $0.isLetter && $0 != "点" && $0 != "円" }
    }

    // MARK: - 確かめる

    /// 足し算で確かめられた道筋と、その点数。
    ///
    /// 強い裏づけ（150点）は「合計の語」（200点）に近い重さにしてある。
    /// 語が読めなかった行でも、足し算が合えば合計として選ばれるように。
    static func arithmeticEvidence(
        for amount: Int,
        summary: Summary,
        itemsTotal: Int?,
        itemsCount: Int,
        itemsCapped: Bool
    ) -> (score: Int, reasons: [String]) {
        var score = 0
        var reasons: [String] = []
        let outerTax = summary.outerTax ?? 0

        if let subtotal = summary.subtotal, outerTax > 0, subtotal + outerTax == amount {
            score += strongEvidence
            reasons.append("小計＋外税と合う")
        }
        if let tendered = summary.tendered, let change = summary.change, change > 0,
           tendered - change == amount {
            score += strongEvidence
            reasons.append("お預り−お釣りと合う")
        }
        // 明細の和は、上限で打ち切っていないときだけ。ぴったり合うのは偶然ではまず起きない。
        // **品が1つだけのときは見ない。** 和がその品の値段そのものなので、品の行が
        // 「明細の和と合う」ことになり、合計の行に勝ってしまう。
        if let itemsTotal, itemsTotal > 0, itemsCount >= 2, !itemsCapped, itemsTotal + outerTax == amount {
            score += strongEvidence
            reasons.append(outerTax > 0 ? "明細の和＋外税とぴったり合う" : "明細の和とぴったり合う")
        }
        if outerTax == 0 {
            if let subtotal = summary.subtotal, subtotal == amount {
                score += weakEvidence
                reasons.append("小計と同じ（内税）")
            }
            if let tax = summary.innerTax, innerTaxMatches(total: amount, tax: tax) {
                score += weakEvidence
                reasons.append("内税の額と合う")
            }
        }
        if summary.payments.contains(amount) {
            score += paymentEvidence
            reasons.append("支払額と同じ")
        }
        return (score, reasons)
    }

    private static let strongEvidence = 150
    private static let weakEvidence = 60
    private static let paymentEvidence = 30

    /// 合計に含まれる消費税が、刷られた内税の額と合うか。
    ///
    /// 8%と10%のどちらか一方の率で、切り捨て・四捨五入・切り上げのどれかで合えばよい。
    /// 2つの率が混ざったレシートでは合わないが、それは「裏づけが無い」だけで減点はしない。
    static func innerTaxMatches(total: Int, tax: Int) -> Bool {
        guard total > 0, tax > 0 else { return false }
        for rate in [0.08, 0.10] {
            let exact = Double(total) * rate / (1 + rate)
            let options = [exact.rounded(.down), exact.rounded(), exact.rounded(.up)]
            if options.contains(Double(tax)) { return true }
        }
        return false
    }

    /// 選んだ合計を足し算と見比べる。
    ///
    /// 食い違うときと、合計の語も足し算の裏づけも無いときは、利用者に確かめてもらう。
    /// **こちらで合計を書き換えることはしない。** 選び直せるのは別の読み方の候補があるときだけで、
    /// それは候補の点数の段階で済んでいる。
    static func amountCheck(best: TotalCandidate?, summary: Summary) -> AmountCheck {
        var reconciled: [Int] = []
        if let subtotal = summary.subtotal, let tax = summary.outerTax, tax > 0 {
            reconciled.append(subtotal + tax)
        }
        if let tendered = summary.tendered, let change = summary.change, change > 0, tendered > change {
            let paid = tendered - change
            if !reconciled.contains(paid) { reconciled.append(paid) }
        }

        var check = AmountCheck(reconciledTotals: reconciled)
        guard let best else { return check }

        if let expected = reconciled.first, !reconciled.contains(best.amount) {
            check.conflicts = true
            check.needsConfirmation = true
            check.note = "合計 \(best.amount.yenText) が、小計と税（またはお預りとお釣り）から計算した "
                + "\(expected.yenText) と合いません。レシートと見比べてください。"
            return check
        }
        if !best.hasKeyword, best.evidence.isEmpty {
            check.needsConfirmation = true
            check.note = "合計の行が読み取れなかったので、いちばん確からしい金額を入れました。レシートと見比べてください。"
        }
        return check
    }
}

// MARK: - 店ごとの書式

extension ReceiptParser {
    /// 行の書き方。数字を除き、照らし合わせる形（`dictionaryKey`）にした文字。
    ///
    /// 「合計 6点 ¥5,302」→「合計点」。点数や金額が変わっても、同じ店の同じ行なら同じになる。
    static func rowLabel(_ text: String) -> String {
        dictionaryKey(text).filter { !("0"..."9").contains($0) }
    }

    /// 保存された合計が刷られていた行の書き方。店ごとの書式（`ReceiptFormat`）として覚える。
    ///
    /// 合計の候補（`totalCandidates`）のうち、その金額でいちばん点の高い行。小計・税・預り・お釣りの
    /// 行は候補に入らないので選ばれない。金額だけの行なら、すぐ上の行（「合計」の語が分かれた行）。
    /// 書き方が2文字に満たなければ覚えない（nil）。
    ///
    /// 読み取った文字（`ReceiptDraft.recognizedText`）は1行が1行のまま並んでいるので、
    /// 位置からまとめ直さずにそのまま行にする（行の多いレシートで、隣の行とまとまらないように）。
    static func totalLabel(forTotal total: Int, inReceiptText text: String) -> String? {
        let rows = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { Row(fragments: [RecognizedLine(text: $0)]) }
        let candidates = totalCandidates(in: rows, summary: summary(of: rows)).filter { $0.amount == total }
        guard let best = candidates.max(by: { $0.score < $1.score }) else { return nil }
        var label = rowLabel(rows[best.rowIndex].text)
        if label.count < 2, best.rowIndex > 0 {
            label = rowLabel(rows[best.rowIndex - 1].text)
        }
        return label.count >= 2 ? label : nil
    }
}
