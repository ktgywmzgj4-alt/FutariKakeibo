import Foundation

/// レシートの読み取り結果から「いつ・どこで・何を・いくら」を取り出す。
///
/// 位置つきの断片をいったん行にまとめ直してから解析する。
/// レシートは品名が左、金額が右に並ぶため、行にまとめないと対応が取れない。
enum ReceiptParser {
    /// 同じ行とみなす縦のずれ。文字の高さに対する割合。
    private static let rowTolerance = 0.7
    private static let maximumItems = 12
    /// 斜めから撮ったときに直す傾きの上限。左端から右端までの間に、
    /// 画像の高さの35%ぶん動くところまで。これを超える値は読み取りの失敗とみなす。
    private static let maximumSkew = 0.35
    /// 傾きの代表値を数えるときの、断片の最小の横幅。
    /// 短い断片は端の座標が近すぎて、傾きが当てにならない。
    private static let skewSampleMinimumWidth = 0.05

    /// 店名として採用しない語。
    ///
    /// 「領収書」は「領収害」と読み違えられる（白馬のカフェのレシート）。
    /// 1文字の違いで素通りしないよう、判定は「領収」までにしてある。
    private static let notMerchantKeywords = [
        "領収", "レシート", "receipt", "合計", "小計", "電話", "tel",
        "登録番号", "責任者", "担当", "レジ", "no.", "様", "店舗", "住所", "取扱",
        "www.", ".com", ".co.jp",
        // 店の案内書き。店名の近くに刷られるので、外さないと店名として拾われる
        // （マクドナルドのレシートで「営業時間 24時間営業」が店名になっていた）。
        "営業時間", "時間営業", "定休", "駐車場のご案内", "ご来店",
        // レシートの下に刷られる求人広告。文字が大きいので店名として拾われやすい。
        "募集", "従業員割引", "副業", "応募", "求人", "アルバイト", "活躍中"
    ]
    /// 店名の前に付いて一緒に読まれるラベル。店名ではないので落とす。
    /// 長いものから先に並べる（「登録名称」を「名称」より先に外す）。
    private static let merchantLabels = ["登録名称", "登録名", "屋号", "店名", "名称"]
    /// 明細として採用しない語。
    private static let notItemKeywords = [
        "合計", "小計", "総計", "お会計", "お支払", "消費税", "内税", "外税", "税額", "税合計",
        "お預り", "お預かり", "お釣", "おつり", "釣銭", "現金", "クレジット", "電子マネー",
        "ポイント", "値引", "割引", "点数", "個数", "お買上", "残高", "電話", "tel", "登録番号",
        // レジや会計処理の記録。品名と金額の並びに見えるが買ったものではない。
        "レジ", "スキャン", "会計機", "精算機", "伝票", "承認", "処理", "取扱", "商品区分", "取引",
        "カード", "会員", "有効期限", "対象", "タイショウ", "テーブル", "人数", "メンテナンス",
        "no.", "no ", "＃", "#", "税率",
        // 給油機やはかりの表示。品名の位置に来るが買ったものではない。
        "数量", "単価", "給油", "リットル"
    ]
    /// 番号を示す語。桁が金額と紛らわしいため、合計を推測するときに外す。
    private static let serialNumberKeywords = [
        "no.", "no ", "＃", "#", "レシート", "会計券", "精算機", "会計機", "伝票",
        "承認", "登録番号", "レジ", "会員", "スキャン", "処理", "通番", "端末番号"
    ]

    // MARK: - 行

    /// 位置の近い断片をまとめた1行。
    struct Row: Equatable, Sendable {
        var fragments: [RecognizedLine]

        var sortedFragments: [RecognizedLine] {
            fragments.sorted { $0.minX < $1.minX }
        }

        var text: String {
            sortedFragments.map(\.text).joined(separator: " ")
        }

        var midY: Double {
            guard !fragments.isEmpty else { return 0 }
            return fragments.map(\.midY).reduce(0, +) / Double(fragments.count)
        }

        var height: Double {
            fragments.map(\.height).max() ?? 0
        }
    }

    /// 斜めから撮ったときの、1枚ぶんの傾き。
    ///
    /// 断片ごとの値はばらつくので中央値を使う。1か所の読み違いでは動かない。
    /// `maximumSkew` を超える値は読み取りの失敗とみなして捨てる。まっすぐ撮った1枚を
    /// でたらめな傾きで動かすほうが、傾きを直さないより害が大きい。
    static func skew(of lines: [RecognizedLine]) -> Double {
        let samples = lines
            .filter { $0.maxX - $0.minX >= skewSampleMinimumWidth }
            .map(\.slope)
            .sorted()
        guard !samples.isEmpty else { return 0 }
        let median = samples[samples.count / 2]
        return abs(median) <= maximumSkew ? median : 0
    }

    /// 傾きぶんを戻した縦位置。その行が画像の左右の中央を通る高さにあたる。
    private static func deskewedMidY(_ line: RecognizedLine, skew: Double) -> Double {
        line.midY - skew * (line.midX - 0.5)
    }

    static func rows(from lines: [RecognizedLine]) -> [Row] {
        // 斜めから撮ると、右にある金額がひとつ下の行の品名と同じ高さに来る。
        // 縦位置だけで並べるとその2つが同じ行にまとまり、値段がひとつずつずれる。
        // 並べる前に傾きぶんを戻す。正面から撮った1枚では傾きが0になり、何も動かない。
        let slant = skew(of: lines)
        let sorted = lines
            .map { (line: $0, y: deskewedMidY($0, skew: slant)) }
            .sorted { $0.y < $1.y }
        guard !sorted.isEmpty else { return [] }

        // 行の間隔は文字の高さで決まる。1枚のレシート全体の代表値を使うほうが、
        // 断片ごとの高さで判断するより安定する。
        let heights = sorted.map { $0.line.height }.sorted()
        let medianHeight = heights[heights.count / 2]
        let tolerance = max(medianHeight * 0.5, 0.003)

        var rows: [Row] = []
        // 同じ行かどうかは「その行の最初の断片」と比べる。行の平均と比べると、
        // 断片が増えるたびに基準が下へずれ、次の行まで巻き込んでしまう。
        var anchors: [Double] = []

        for entry in sorted {
            if let anchor = anchors.last, abs(entry.y - anchor) <= tolerance {
                rows[rows.count - 1].fragments.append(entry.line)
                continue
            }
            rows.append(Row(fragments: [entry.line]))
            anchors.append(entry.y)
        }
        return rows
    }

    // MARK: - 入口

    static func parse(
        lines: [RecognizedLine],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ReceiptDraft {
        let rows = rows(from: lines)
        let shopName = merchant(from: rows)
        let totalIndex = totalRowIndex(in: rows)
        let recognizedText = rows.map(\.text).joined(separator: "\n")
        let found = items(from: rows, before: totalIndex)
        // 明細が読めていれば、合計の候補が妥当かどうかの手がかりになる。
        let itemsTotal = found.isEmpty ? nil : found.reduce(0) { $0 + $1.amount }

        return ReceiptDraft(
            merchant: shopName,
            amount: totalAmount(from: rows, itemsTotal: itemsTotal),
            date: receiptDate(from: rows, now: now, calendar: calendar),
            items: found,
            suggestedCategory: category(from: recognizedText, merchant: shopName, items: found),
            recognizedText: recognizedText,
            shopKey: MerchantKey.make(fromReceiptText: recognizedText, merchant: shopName)
        )
    }

    static func parse(
        text: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ReceiptDraft {
        parse(lines: RecognizedLine.lines(fromPlainText: text), now: now, calendar: calendar)
    }

    // MARK: - どこで

    /// 店名を探す範囲。長いレシートで明細まで候補に入らないよう、行数で区切る。
    private static let merchantSearchRows = 10

    /// 店名の候補と、その点数。
    struct MerchantCandidate: Equatable, Sendable {
        var text: String
        var rowIndex: Int
        var score: Int
        var reason: String
    }

    static func merchant(from rows: [Row]) -> String {
        let candidates = merchantCandidates(in: rows)
        logCandidates("店名", candidates.map { ($0.text, $0.score, $0.reason) })
        guard let best = candidates.max(by: { $0.score < $1.score }) else { return "" }

        // 上部にはロゴしか無く、支店名だけが文字として読めることがある
        // （コノミヤのレシートで「城西店」だけになった）。
        // レシートのどこかに「チェーン名＋支店名」が刷られていれば、そちらを使う。
        // **完全に読めなくても、チェーン名を落とさない。**
        let fuller = candidates
            .filter { $0.text != best.text && $0.text.contains(best.text) }
            .max { $0.text.count < $1.text.count }
        let chosen = fuller ?? best
        logChoice("店名", chosen.text, chosen.score, fuller == nil ? chosen.reason : "チェーン名を拾い直した")
        return cleanedMerchant(chosen.text)
    }

    /// 店名の候補を集めて点数をつける。
    ///
    /// 候補はレシート全体から集める。点は**上にあること**をいちばん重く見る。
    /// 下の広告にもチェーン名が出るので、集めるのは全体、選ぶのは上、という形。
    static func merchantCandidates(in rows: [Row]) -> [MerchantCandidate] {
        let heights = rows.map(\.height).sorted()
        let medianHeight = heights.isEmpty ? 0.02 : max(heights[heights.count / 2], 0.001)
        var seen: [String: Int] = [:]
        for row in rows where isMerchantCandidate(row) {
            seen[row.text, default: 0] += 1
        }

        return rows.enumerated().compactMap { index, row in
            guard isMerchantCandidate(row) else { return nil }
            var score = 0
            var reasons: [String] = []
            if index < merchantSearchRows {
                score += 60
                reasons.append("レシートの上")
            }
            if row.text.contains("店") {
                score += 40
                reasons.append("店が付く")
            }
            // 大きい文字ほど店名らしい。ロゴが飛び抜けても効きすぎないよう頭を抑える。
            let size = min(50, Int(30.0 * row.height / medianHeight))
            score += size
            reasons.append("文字の大きさ\(size)")
            if (seen[row.text] ?? 0) >= 2 {
                score += 30
                reasons.append("2か所以上に出る")
            }
            return MerchantCandidate(
                text: row.text,
                rowIndex: index,
                score: score,
                reason: reasons.joined(separator: " / ")
            )
        }
    }

    static func merchant(from lines: [String]) -> String {
        merchant(from: rows(from: RecognizedLine.lines(fromPlainText: lines.joined(separator: "\n"))))
    }

    private static func isMerchantCandidate(_ row: Row) -> Bool {
        let text = row.text
        let lower = text.lowercased()
        if notMerchantKeywords.contains(where: { lower.contains($0) }) { return false }
        if text.count > 30 || text.count < 2 { return false }
        if !containsLetters(text) { return false }
        if looksLikeDate(text) { return false }
        if looksLikePhoneNumber(text) { return false }
        if looksLikeAddress(text) { return false }
        // 末尾が金額の行は明細。店名の行に値段は付かない。
        if endsWithPrice(text) { return false }
        // 明細の先頭につく印。
        if text.hasPrefix("*") || text.hasPrefix("＊") { return false }
        // 数字ばかりの行は店名ではない。
        let digits = text.filter(\.isNumber).count
        return Double(digits) / Double(text.count) < 0.4
    }

    private static func endsWithPrice(_ text: String) -> Bool {
        normalizedDigits(text).range(
            of: #"[0-9]{1,7}\s*円?\s*[*※＊軽外内)）]?\s*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func cleanedMerchant(_ text: String) -> String {
        var value = text
        // 「登録名称 株式会社マナの森」のように、ラベルごと1行に読まれることがある。
        // 頭に付いているときだけ落とす。店名の途中に出てきたら触らない。
        for label in merchantLabels where value.hasPrefix(label) {
            value = String(value.dropFirst(label.count))
            break
        }
        return value
            .trimmingCharacters(in: CharacterSet(charactersIn: " 　*※-–—・|:："))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - いくら

    /// 明細を探す範囲の終わり。ここより下は支払いの内訳なので品名は無い。
    private static func totalRowIndex(in rows: [Row]) -> Int? {
        rows.lastIndex { row in
            hasStrongTotalKeyword(row.text)
                && !isNeverTotalRow(row.text)
                && !isSideAmountRow(row.text)
        }
    }

    /// 読めた明細の和と見比べて、合計としてありえる大きさか。**上下の両方を見る。**
    ///
    /// 下は、値引きがあると合計が和より小さくなるので少し許す（6割まで）。
    /// 上は、外税や読み落とした明細のぶんだけ大きくなる。桁がひとつ増えた答え
    /// （3,374 のつもりが 33,740）を落とすのが目的なので、3倍までは許す。
    ///
    /// **明細を上限まで拾ったときは、上を見ない。** そこで打ち切っただけで、
    /// 下にまだ品物が続いているかもしれない。打ち切った和と比べても意味がない。
    static func isConsistentWithItems(_ amount: Int, items: [ReceiptItem]) -> Bool {
        let itemsTotal = items.reduce(0) { $0 + $1.amount }
        guard itemsTotal > 0 else { return true }
        guard Double(amount) >= Double(itemsTotal) * lowerConsistencyRatio else { return false }
        guard items.count < maximumItems else { return true }
        return Double(amount) <= Double(itemsTotal) * upperConsistencyRatio
    }

    private static let lowerConsistencyRatio = 0.6
    private static let upperConsistencyRatio = 3.0

    /// 合計の候補。どの行のどの数字を、なぜ選んだか（選ばなかったか）を持つ。
    struct TotalCandidate: Equatable, Sendable {
        var amount: Int
        var rowIndex: Int
        var score: Int
        var reason: String
    }

    /// 合計を示す語。いちばん強い手がかり。
    private static let strongTotalKeywords = [
        "合計", "総計", "お会計", "お支払", "支払合計", "ご請求", "現計", "お買上", "クレジット"
    ]
    /// 数字は載っているが支払額ではない行。**合計の語があっても**候補にしない。
    private static let neverTotalKeywords = [
        "点数", "買上点", "単価", "数量", "ポイント", "残高", "前回", "有効期限", "会員", "枚数"
    ]
    /// 税・値引き・預り金の行。合計の語が同じ行に無ければ候補にしない。
    /// 「税込合計」のように合計の語がある行は残す。
    private static let sideAmountKeywords = [
        "税率", "対象額", "対象計", "消費税", "内税", "外税", "税額", "小計",
        "値引", "割引", "お預り", "お預かり", "預り", "お釣", "おつり", "釣銭"
    ]

    private static func hasStrongTotalKeyword(_ text: String) -> Bool {
        let lower = text.lowercased()
        return strongTotalKeywords.contains { lower.contains($0) } || lower.contains("total")
    }

    private static func isNeverTotalRow(_ text: String) -> Bool {
        let lower = text.lowercased()
        return neverTotalKeywords.contains { lower.contains($0) }
    }

    private static func isSideAmountRow(_ text: String) -> Bool {
        let lower = text.lowercased()
        return sideAmountKeywords.contains { lower.contains($0) }
    }

    /// 合計の候補を集めて点数をつける。
    ///
    /// **最大値でも最後の数字でもなく、点数のいちばん高いものを採る。**
    /// レシートには金額と同じ形の数字が山ほどある（時刻・伝票番号・税額・単価）。
    /// どれを外すかを先に決め、残ったものに手がかりの数で点をつける。
    static func totalCandidates(in rows: [Row], itemsTotal: Int? = nil) -> [TotalCandidate] {
        // 「合計」の語と金額が別の行に分かれて読まれることがある。
        // 語の下で最初に金額が出てくる行にも、少し低い点を渡す。
        var lookahead: Set<Int> = []
        for index in rows.indices where hasStrongTotalKeyword(rows[index].text) {
            guard amounts(in: rows[index].text).isEmpty else { continue }
            var next = index + 1
            while next < rows.count, next <= index + totalLookaheadRows {
                let text = rows[next].text
                if !isSideAmountRow(text), !isNeverTotalRow(text), !amounts(in: text).isEmpty {
                    lookahead.insert(next)
                    break
                }
                next += 1
            }
        }

        var found: [(amount: Int, index: Int, marked: Bool)] = []
        var seen: [Int: Int] = [:]
        for (index, row) in rows.enumerated() {
            let text = row.text
            if looksLikePhoneNumber(text) || looksLikeDate(text) || looksLikeSerialNumber(text) {
                continue
            }
            if isNeverTotalRow(text) { continue }
            let strong = hasStrongTotalKeyword(text)
            if !strong, isSideAmountRow(text) { continue }

            let marked = currencyAmounts(in: text).filter(isPlausibleAmount)
            let values = marked.isEmpty ? amounts(in: text).filter(isPlausibleAmount) : marked
            for value in values {
                found.append((value, index, !marked.isEmpty))
                seen[value, default: 0] += 1
            }
        }

        let lastIndex = max(rows.count - 1, 1)
        return found.map { entry in
            var score = 0
            var reasons: [String] = []
            if hasStrongTotalKeyword(rows[entry.index].text) {
                score += 200
                reasons.append("合計の語")
            } else if lookahead.contains(entry.index) {
                score += 170
                reasons.append("合計の語の直下")
            }
            if entry.marked {
                score += 40
                reasons.append("通貨の印")
            }
            let depth = Int(30.0 * Double(entry.index) / Double(lastIndex))
            score += depth
            reasons.append("下から\(depth)")
            if let itemsTotal, itemsTotal > 0 {
                if entry.amount >= itemsTotal, Double(entry.amount) <= Double(itemsTotal) * 1.3 {
                    score += 80
                    reasons.append("明細の和と合う")
                } else if Double(entry.amount) < Double(itemsTotal) * 0.6 {
                    // 明細の和より桁がひとつ小さい。読み違いとみなす。
                    score -= 250
                    reasons.append("明細の和より小さすぎる")
                }
            }
            if (seen[entry.amount] ?? 0) >= 2 {
                score += 40
                reasons.append("2か所以上に出る")
            }
            return TotalCandidate(
                amount: entry.amount,
                rowIndex: entry.index,
                score: score,
                reason: reasons.joined(separator: " / ")
            )
        }
    }

    static func totalAmount(from rows: [Row], itemsTotal: Int? = nil) -> Int? {
        let candidates = totalCandidates(in: rows, itemsTotal: itemsTotal)
        logCandidates("合計", candidates.map { ("\($0.amount)", $0.score, $0.reason) })
        guard let best = candidates.max(by: { lhs, rhs in
            // 点数が同じなら大きいほうを採る。合計は明細より小さくならない。
            (lhs.score, lhs.amount) < (rhs.score, rhs.amount)
        }) else { return nil }
        logChoice("合計", "\(best.amount)", best.score, best.reason)
        return best.amount
    }

    static func totalAmount(from lines: [String]) -> Int? {
        totalAmount(from: rows(from: RecognizedLine.lines(fromPlainText: lines.joined(separator: "\n"))))
    }

    /// 「合計」の語から下へ何行まで金額を探すか。
    private static let totalLookaheadRows = 3

    /// レシート番号や伝票番号の行。金額と桁が近く紛らわしい。
    private static func looksLikeSerialNumber(_ text: String) -> Bool {
        let lower = text.lowercased()
        return serialNumberKeywords.contains { lower.contains($0) }
    }

    private static func isPlausibleAmount(_ value: Int) -> Bool {
        value >= 1 && value <= 9_999_999
    }

    // MARK: - 何を

    /// 明細が始まらない冒頭の行数。ロゴや店名の誤読を品名として拾わないため。
    private static let headerRows = 3

    static func items(from rows: [Row], before totalIndex: Int?) -> [ReceiptItem] {
        let limit = totalIndex ?? rows.count
        // 実物のレシートは必ず数行の見出しから始まる。短い入力では飛ばさない。
        let start = rows.count >= 8 ? min(headerRows, limit) : 0
        guard start < limit else { return [] }
        var results: [ReceiptItem] = []

        for row in rows[start..<limit] {
            guard let item = item(from: row) else { continue }
            results.append(item)
            if results.count >= maximumItems { break }
        }
        return results
    }

    private static func item(from row: Row) -> ReceiptItem? {
        let lower = row.text.lowercased()
        if notItemKeywords.contains(where: { lower.contains($0) }) { return nil }
        if looksLikeDate(row.text) || looksLikePhoneNumber(row.text) { return nil }
        if looksLikeAddress(row.text) { return nil }
        // 税率や割引率の行。金額の並びに見えるが買ったものではない。
        if row.text.contains("%") || row.text.contains("％") { return nil }
        // 「2コX単118」のような数量と単価の行。品名ではない。
        if row.text.range(of: #"[0-9]\s*[コ個][x×X]\s*単"#, options: .regularExpression) != nil { return nil }

        let fragments = row.sortedFragments
        guard fragments.count >= 2 else { return itemFromText(row.text) }

        let nameText = fragments.dropLast().map(\.text).joined(separator: " ")
        // 品名の側がすでに金額で終わっているなら、右端の断片は隣の行のもの。
        // 巻き込んだ金額ではなく、品名についている金額を使う。
        if endsWithPrice(nameText) {
            return itemFromText(nameText)
        }

        // 一番右の断片が金額、その左が品名という並びを前提にする。
        guard
            let price = amounts(in: fragments[fragments.count - 1].text).last,
            isPlausibleAmount(price), price <= 999_999
        else { return nil }

        let name = cleanedItemName(nameText)
        guard isPlausibleItemName(name) else { return nil }
        return ReceiptItem(name: name, amount: price)
    }

    /// 品名と金額が地続きに読まれた場合。末尾の数字を金額として切り出す。
    private static func itemFromText(_ source: String) -> ReceiptItem? {
        let text = normalizedDigits(source)
        guard
            let match = text.range(of: #"([0-9]{1,6})\s*円?\s*[*※＊軽外内]?\s*$"#, options: .regularExpression)
        else { return nil }
        let priceText = text[match].filter(\.isNumber)
        guard let price = Int(priceText), isPlausibleAmount(price), price <= 999_999 else { return nil }

        let name = cleanedItemName(String(text[text.startIndex..<match.lowerBound]))
        guard isPlausibleItemName(name) else { return nil }
        return ReceiptItem(name: name, amount: price)
    }

    private static func cleanedItemName(_ text: String) -> String {
        var name = text
            .trimmingCharacters(in: CharacterSet(charactersIn: " 　*※＊・|-–—軽外内"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 「外8 1501 鮮魚」のように、税区分と商品コードが品名の前につく。
        // 品名だけ残したいので、先頭に並ぶ数字とその区切りを落とす。
        while let range = name.range(of: #"^[0-9]{1,6}\s*"#, options: .regularExpression) {
            let stripped = String(name[range.upperBound...])
            if stripped.isEmpty { break }
            name = stripped
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isPlausibleItemName(_ name: String) -> Bool {
        guard name.count >= 2, name.count <= 24, containsLetters(name) else { return false }
        let digits = name.filter(\.isNumber).count
        return Double(digits) / Double(name.count) < 0.5
    }

    // MARK: - いつ

    static func receiptDate(
        from rows: [Row],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        for row in rows {
            if let date = date(in: row.text, now: now, calendar: calendar) {
                return date
            }
        }
        return nil
    }

    static func date(in text: String, now: Date = .now, calendar: Calendar = .current) -> Date? {
        let value = normalizedDigits(text)
        let currentYear = calendar.component(.year, from: now)
        // 年が書いてあるのに日付として成り立たない場合は読み違いなので、
        // 年なしの解釈に落として今年の日付を作ってしまわないようにする。
        var sawExplicitYear = false

        // 令和は2019年が元年。R6のような略記も拾う。
        if let match = firstMatch(#"(?:令和|R)\s*(\d{1,2})\s*[年./-]\s*(\d{1,2})\s*[月./-]\s*(\d{1,2})"#, in: value),
           match.count == 3,
           let era = Int(match[0]), let month = Int(match[1]), let day = Int(match[2]) {
            sawExplicitYear = true
            if let date = makeDate(year: 2018 + era, month: month, day: day, now: now, calendar: calendar) {
                return date
            }
        }
        if let match = firstMatch(#"(20\d{2})\s*[年./-]\s*(\d{1,2})\s*[月./-]\s*(\d{1,2})"#, in: value),
           match.count == 3,
           let year = Int(match[0]), let month = Int(match[1]), let day = Int(match[2]) {
            sawExplicitYear = true
            if let date = makeDate(year: year, month: month, day: day, now: now, calendar: calendar) {
                return date
            }
        }
        // 26/08/29 のような2桁年。
        if let match = firstMatch(#"(?<!\d)(\d{2})\s*[./-]\s*(\d{1,2})\s*[./-]\s*(\d{1,2})(?!\d)"#, in: value),
           match.count == 3,
           let year = Int(match[0]), let month = Int(match[1]), let day = Int(match[2]) {
            sawExplicitYear = true
            if let date = makeDate(year: 2000 + year, month: month, day: day, now: now, calendar: calendar) {
                return date
            }
        }
        guard !sawExplicitYear else { return nil }

        // 年のない 8月29日 は、その年のものとして扱う。
        if let match = firstMatch(#"(?<!\d)(\d{1,2})\s*[月/]\s*(\d{1,2})\s*日?(?!\d)"#, in: value),
           match.count == 2,
           let month = Int(match[0]), let day = Int(match[1]) {
            if let date = makeDate(year: currentYear, month: month, day: day, now: now, calendar: calendar) {
                return date
            }
            // 年末年始をまたいだレシートは前の年のもの。
            if let date = makeDate(year: currentYear - 1, month: month, day: day, now: now, calendar: calendar) {
                return date
            }
        }
        return nil
    }


    private static func makeDate(
        year: Int,
        month: Int,
        day: Int,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return nil
        }
        // 先の日付や何年も前の日付は読み違いとみなす。
        guard let earliest = calendar.date(byAdding: .year, value: -3, to: now),
              let latest = calendar.date(byAdding: .day, value: 1, to: now)
        else { return date }
        return (date >= earliest && date <= latest) ? date : nil
    }

    // MARK: - カテゴリ

    private static let categoryRules: [(ExpenseCategory, [String])] = [
        (.transportation, ["鉄道", "タクシー", "駐車場", "高速道路", "ガソリン", "eneos", "乗車券", "定期券", "交通"]),
        (.utilities, ["電気", "ガス", "水道", "通信", "携帯"]),
        (.health, ["病院", "医院", "薬局", "クリニック", "歯科", "ドラッグ"]),
        (.beauty, ["美容", "衣料", "服", "ユニクロ", "gu "]),
        (.travel, ["ホテル", "旅館", "宿泊", "レンタカー", "航空"]),
        // 外食。ここに並べるのは**店の名前として出てくる語**だけにする。
        // 「コーヒー」「バーガー」のような商品名を入れると、スーパーで
        // それを買っただけの買い物まで外食になってしまう。
        (.dining, [
            "レストラン", "居酒屋", "カフェ", "ラーメン", "食堂", "coffee",
            "マクドナルド", "ケンタッキー", "モスバーガー", "バーガーキング", "ロッテリア",
            "スターバックス", "ドトール", "コメダ", "タリーズ", "サイゼリヤ", "ガスト",
            "すき家", "吉野家", "松屋", "丸亀", "はなまる", "cocoいちばん", "ココイチ",
            "びっくりドンキー", "サイゼ", "焼肉", "寿司", "そば処", "うどん", "牛丼",
            "定食", "珈琲", "喫茶", "ピザ", "restaurant"
        ]),
        (.household, ["ホームセンター", "日用品", "ダイソー", "ニトリ"]),
        // スーパーの名前は外食より後に見るので、「マックスバリュ」のように
        // 外食の語を含みうる名前は、ここに明示して取り戻す。
        (.groceries, [
            "スーパー", "食品", "コンビニ", "market", "mart", "ローソン", "セブン",
            "ファミリーマート", "マックスバリュ", "イオン", "業務スーパー", "青果", "精肉", "鮮魚",
            "コノミヤ", "バロー", "アピタ", "ヤオコー", "ライフ", "西友", "サミット", "生協", "コープ",
            // 買ったものの名前。店名で決まらないときの二段目に効く。
            // **スーパーにしか無いもの**を選んである。外食の店にも出るものは入れない。
            "牛乳", "たまご", "野菜", "豆腐", "納豆", "ヨーグルト", "しめじ", "ほうれん草",
            "キャベツ", "にんじん", "玉ねぎ", "食パン", "バナナ", "生クリーム", "ベーコン"
        ]),
        (.entertainment, ["映画", "シネマ", "カラオケ", "チケット"])
    ]

    /// 買い物の種類を決める。手がかりは **店名 → 買ったもの → レシート全文** の順。
    ///
    /// 店名はレシート全体の性格を最もよく表すので、まず店名だけで判定する。
    /// 次が買ったものの名前。全文はいちばん最後にする。全文には案内書きや
    /// 但し書きが混ざっていて、「日用品」が1行あるだけでスーパーの買い物が
    /// 日用品になってしまうため。
    static func category(
        from text: String,
        merchant: String = "",
        items: [ReceiptItem] = []
    ) -> ExpenseCategory {
        if let matched = bestMatch(in: merchant) {
            return matched
        }
        let itemNames = items.map(\.name).joined(separator: " ")
        if let matched = bestMatch(in: itemNames) {
            return matched
        }
        return bestMatch(in: text) ?? .other
    }

    /// 当てはまった語の多いカテゴリを選ぶ。同数なら定義順で先にあるものを選ぶ。
    private static func bestMatch(in text: String) -> ExpenseCategory? {
        guard !text.isEmpty else { return nil }
        let value = text.lowercased()
        var best: (category: ExpenseCategory, hits: Int)?

        for (category, keywords) in categoryRules {
            let hits = keywords.filter { value.contains($0) }.count
            if hits > (best?.hits ?? 0) {
                best = (category, hits)
            }
        }
        return best?.category
    }

    // MARK: - 何を見て決めたか（DEBUGのみ）

    /// 候補と点数を出す。実機で外したとき、何を見て決めたかを追えるようにする。
    /// 配信するビルドでは1行も出ない。
    private static func logCandidates(_ label: String, _ entries: [(String, Int, String)]) {
        #if DEBUG
        guard !entries.isEmpty else {
            print("[レシート解析] \(label): 候補なし")
            return
        }
        print("[レシート解析] \(label) の候補 \(entries.count)件")
        for entry in entries.sorted(by: { $0.1 > $1.1 }) {
            print("  \(entry.1)点  \(entry.0)  ← \(entry.2)")
        }
        #endif
    }

    private static func logChoice(_ label: String, _ value: String, _ score: Int, _ reason: String) {
        #if DEBUG
        print("[レシート解析] \(label) は「\(value)」に決めた（\(score)点 / \(reason)）")
        #endif
    }

    // MARK: - 文字の判定

    /// 数字と通貨記号だけを揃える。文字列全体を半角化すると、
    /// 品名のカタカナまで半角になってしまう。
    private static func normalizedDigits(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            if character == "," || character == "，" || character == "¥" || character == "￥" {
                continue
            }
            let scalars = character.unicodeScalars
            if scalars.count == 1,
               let scalar = scalars.first,
               scalar.value >= 0xFF10, scalar.value <= 0xFF19 {
                result.append(Character(UnicodeScalar(UInt8(scalar.value - 0xFF10 + 48))))
            } else {
                result.append(character)
            }
        }
        return joinedThousands(result)
    }

    /// 桁区切りのカンマが **ピリオド** として読まれたものをつなぐ。
    ///
    /// コノミヤのレシートで `¥3,374` が `¥3. 374` と読まれ、3 と 374 に割れて
    /// 合計が3円になった。つなぐのは次を**すべて**満たすときだけ。
    ///
    /// - ピリオドの前が数字
    /// - その数字の並びが `0` ひとつだけではない（`0.398` は重さ。金額は0で始まらない）
    /// - ピリオドの後ろに数字が **ちょうど3桁** 続く（`19.12` は給油量。桁区切りではない）
    private static func joinedThousands(_ text: String) -> String {
        guard text.contains(".") else { return text }
        let characters = Array(text)
        var result = ""
        var index = 0
        while index < characters.count {
            guard characters[index] == ".",
                  let previous = result.last, previous.isNumber,
                  !integerPartIsZero(result)
            else {
                result.append(characters[index])
                index += 1
                continue
            }
            var ahead = index + 1
            if ahead < characters.count, characters[ahead] == " " || characters[ahead] == "\u{3000}" {
                ahead += 1
            }
            let digits = characters[ahead...].prefix { $0.isNumber }
            guard digits.count == 3 else {
                result.append(characters[index])
                index += 1
                continue
            }
            // ピリオド（と続く空白）を飛ばして、前後の数字をつなげる。
            index = ahead
        }
        return result
    }

    /// ピリオドの前の数字の並びが `0` ひとつだけか。`0.398` のような重さを見分ける。
    private static func integerPartIsZero(_ text: String) -> Bool {
        let digits = text.reversed().prefix { $0.isNumber }
        return digits.count == 1 && digits.first == "0"
    }

    /// 数字の並びから金額を拾う。
    ///
    /// レシートには金額と紛らわしい数字が多い。店番号 `SS-38125`、商品コード `0200`、
    /// 単価 `@155`、給油量 `19.12(L)`、カード番号の末尾 `XXXX6941`。
    /// どれも桁数だけでは金額と見分けがつかないので、前後に何が付いているかで落とす。
    private static func amounts(in line: String) -> [Int] {
        let normalized = normalizedDigits(line)
        guard let regex = try? NSRegularExpression(
            // 末尾に % を足したのは、「(税率 8%対象額」の 8 を合計として拾ったため。
            pattern: #"(?<![-0-9A-Za-z@－])(?<![0-9]\.)([0-9]{1,7})(?![-0-9A-Za-z－%％])(?!\.[0-9])"#
        ) else {
            return []
        }
        let range = NSRange(normalized.startIndex..., in: normalized)
        return regex.matches(in: normalized, range: range).compactMap { match in
            guard let swiftRange = Range(match.range(at: 1), in: normalized) else { return nil }
            let digits = normalized[swiftRange]
            // 先頭が0の数字は商品コードや端末番号。金額が0で始まることはない。
            if digits.count > 1, digits.hasPrefix("0") { return nil }
            return Int(digits)
        }
    }

    /// ¥ や 円 の付いた数字だけを拾う。
    /// 店番号にも伝票番号にも通貨の印は付かないので、これだけで大半を落とせる。
    private static func currencyAmounts(in line: String) -> [Int] {
        let line = joinedThousands(line)
        let patterns = [#"[¥￥]\s*([0-9,０-９，]{1,11})"#, #"([0-9,０-９，]{1,11})\s*円"#]
        var found: [Int] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(line.startIndex..., in: line)
            for match in regex.matches(in: line, range: range) {
                guard let swiftRange = Range(match.range(at: 1), in: line) else { continue }
                let digits = normalizedDigits(String(line[swiftRange]))
                if digits.count > 1, digits.hasPrefix("0") { continue }
                if let value = Int(digits) { found.append(value) }
            }
        }
        return found
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<match.numberOfRanges).compactMap { group in
            guard let range = Range(match.range(at: group), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func containsLetters(_ text: String) -> Bool {
        text.range(of: "[A-Za-zぁ-んァ-ヶ一-龠]", options: .regularExpression) != nil
    }

    private static func looksLikeDate(_ text: String) -> Bool {
        normalizedDigits(text).range(
            of: #"\d{1,4}\s*[年./-]\s*\d{1,2}\s*[月./-]\s*\d{1,2}"#,
            options: .regularExpression
        ) != nil
    }

    private static func looksLikePhoneNumber(_ text: String) -> Bool {
        let value = normalizedDigits(text)
        if value.range(of: #"(tel|TEL|電話)"#, options: .regularExpression) != nil { return true }
        return value.range(of: #"(?<!\d)0\d{1,4}[-‐－]\d{1,4}[-‐－]\d{3,4}(?!\d)"#, options: .regularExpression) != nil
            || value.range(of: #"(?<!\d)\d{10,11}(?!\d)"#, options: .regularExpression) != nil
    }

    /// 住所の行かどうか。
    ///
    /// **1文字あるだけで住所と決めつけない。** 以前は 都道府県市区町村 のどれかが
    /// 入っていれば住所としていたので、「マクドナルド城町店」の **町** に当たって
    /// 店名候補から消えていた。日本の店名には 町・市・区 がふつうに入る。
    ///
    /// 住所には必ず番地の数字が続く。店名には続かない。そこで見分ける。
    private static func looksLikeAddress(_ text: String) -> Bool {
        if text.contains("丁目") || text.contains("番地") { return true }
        // 「店」が入る行は店名。住所の行に店の名前が刷られることはまずない。
        if text.contains("店") { return false }
        // 都道府県の名前は住所にしか出てこない。「長野県 北安曇郡」のように
        // 番地が別の行に折り返されていても、ここで住所と分かる。
        if text.range(of: "東京都|北海道|大阪府|京都府|[一-龠]{2,3}県", options: .regularExpression) != nil {
            return true
        }
        // 市区町村・郡のあとに番地の数字が続く形。店名に番地は付かない。
        return text.range(of: "[市区町村郡].*[0-9]", options: .regularExpression) != nil
    }
}
