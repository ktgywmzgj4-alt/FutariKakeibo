import Foundation

/// レシートの読み取り結果から「いつ・どこで・何を・いくら」を取り出す。
///
/// 位置つきの断片をいったん行にまとめ直してから解析する。
/// レシートは品名が左、金額が右に並ぶため、行にまとめないと対応が取れない。
enum ReceiptParser {
    /// 同じ行とみなす縦のずれ。文字の高さに対する割合。
    private static let rowTolerance = 0.7
    private static let maximumItems = 12

    /// 合計を示す語。これがある行の金額を最優先で使う。
    private static let totalKeywords = ["合計", "総計", "お会計", "お支払", "ご請求", "total"]
    /// 合計と紛らわしいが違うもの。これらを含む行は合計として扱わない。
    private static let notTotalKeywords = [
        "小計", "対象計", "内税", "外税", "消費税", "税額",
        "お預り", "お預かり", "預り", "お釣", "おつり", "釣銭", "現金",
        "ポイント", "値引", "割引", "点数", "個数", "残高", "前回"
    ]
    /// 店名として採用しない語。
    private static let notMerchantKeywords = [
        "領収書", "領収証", "レシート", "receipt", "合計", "小計", "電話", "tel",
        "登録番号", "責任者", "担当", "レジ", "no.", "様", "店舗", "住所", "取扱"
    ]
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

    static func rows(from lines: [RecognizedLine]) -> [Row] {
        let sorted = lines.sorted { $0.midY < $1.midY }
        guard !sorted.isEmpty else { return [] }

        // 行の間隔は文字の高さで決まる。1枚のレシート全体の代表値を使うほうが、
        // 断片ごとの高さで判断するより安定する。
        let heights = sorted.map(\.height).sorted()
        let medianHeight = heights[heights.count / 2]
        let tolerance = max(medianHeight * 0.5, 0.003)

        var rows: [Row] = []
        // 同じ行かどうかは「その行の最初の断片」と比べる。行の平均と比べると、
        // 断片が増えるたびに基準が下へずれ、次の行まで巻き込んでしまう。
        var anchors: [Double] = []

        for line in sorted {
            if let anchor = anchors.last, abs(line.midY - anchor) <= tolerance {
                rows[rows.count - 1].fragments.append(line)
                continue
            }
            rows.append(Row(fragments: [line]))
            anchors.append(line.midY)
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
            suggestedCategory: category(from: recognizedText, merchant: shopName),
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

    static func merchant(from rows: [Row]) -> String {
        let head = Array(rows.prefix(merchantSearchRows))
        let candidates = head.filter { isMerchantCandidate($0) }
        guard !candidates.isEmpty else {
            // 上の方が全部除外された場合だけ、全体から探す。
            let fallback = rows.filter { isMerchantCandidate($0) }
            return cleanedMerchant(fallback.first?.text ?? "")
        }

        // 「店」で終わる行があれば、それが一番はっきりした店名。
        // ロゴの読み違いより、本文に刷られた正式な店名を優先する。
        let named = candidates.filter { $0.text.contains("店") }
        if let best = named.max(by: { $0.text.count < $1.text.count }) {
            return cleanedMerchant(best.text)
        }

        // なければ、上部で一番大きな文字の行。
        let tallest = candidates.max { lhs, rhs in
            lhs.height < rhs.height
        }
        return cleanedMerchant(tallest?.text ?? candidates[0].text)
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
        text
            .trimmingCharacters(in: CharacterSet(charactersIn: " 　*※-–—・|"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - いくら

    private static func totalRowIndex(in rows: [Row]) -> Int? {
        rows.lastIndex { isTotalRow($0) }
    }

    private static func isTotalRow(_ row: Row) -> Bool {
        let lower = row.text.lowercased()
        guard totalKeywords.contains(where: { lower.contains($0) }) else { return false }
        return !notTotalKeywords.contains { lower.contains($0) }
    }

    static func totalAmount(from rows: [Row], itemsTotal: Int? = nil) -> Int? {
        if let index = totalRowIndex(in: rows) {
            // 「合計」は大きく刷られることが多く、語と金額が別の行として
            // 読まれることがある。同じ行に無ければ次の行も見る。
            var candidates = amounts(in: rows[index].text)
            if candidates.isEmpty, index + 1 < rows.count {
                candidates = amounts(in: rows[index + 1].text)
            }
            if let amount = candidates.filter({ isPlausibleAmount($0) }).max() {
                return amount
            }
        }

        // 合計が読めなかった場合。「合計」が大きく刷られていると、次の行の
        // 「内税分消費税」まで巻き込んで1行になり、合計の行だと判定できなくなる。
        //
        // このとき単純な最大値を取ると、店番号や端末番号のほうが桁が大きいので
        // 必ずそちらを拾う（Selfixのレシートで店番号 SS-38125 を合計にしていた）。
        // ¥ の付いた数字があれば、それだけを見る。番号に通貨の印は付かない。
        let usable = Array(rows.enumerated()).filter { pair in
            !looksLikePhoneNumber(pair.element.text)
                && !looksLikeDate(pair.element.text)
                && !looksLikeSerialNumber(pair.element.text)
        }
        let marked = usable.flatMap { pair in
            currencyAmounts(in: pair.element.text)
                .filter(isPlausibleAmount)
                .map { (index: pair.offset, amount: $0) }
        }
        let plain = usable.flatMap { pair in
            amounts(in: pair.element.text)
                .filter(isPlausibleAmount)
                .map { (index: pair.offset, amount: $0) }
        }
        let numbered = marked.isEmpty ? plain : marked
        guard !numbered.isEmpty else { return nil }

        // 明細が読めているなら、合計はその和以上で、税を足しても大きくは離れない。
        // 条件に合うもののうち、レシートの下にあるものほど合計らしい。
        if let itemsTotal, itemsTotal > 0 {
            let upperBound = Int(Double(itemsTotal) * 1.3)
            let plausible = numbered.filter { $0.amount >= itemsTotal && $0.amount <= upperBound }
            if let best = plausible.max(by: { $0.index < $1.index }) {
                return best.amount
            }
        }
        return numbered.map(\.amount).max()
    }

    static func totalAmount(from lines: [String]) -> Int? {
        totalAmount(from: rows(from: RecognizedLine.lines(fromPlainText: lines.joined(separator: "\n"))))
    }

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
        (.dining, ["レストラン", "居酒屋", "カフェ", "ラーメン", "食堂", "coffee"]),
        (.household, ["ホームセンター", "日用品", "ダイソー", "ニトリ"]),
        (.groceries, ["スーパー", "食品", "コンビニ", "market", "mart", "ローソン", "セブン", "ファミリーマート"]),
        (.entertainment, ["映画", "シネマ", "カラオケ", "チケット"])
    ]

    static func category(from text: String, merchant: String = "") -> ExpenseCategory {
        // 店名はレシート全体の性格を最もよく表すため、まず店名だけで判定する。
        // 明細に「日用品」が1行あるだけでスーパーの買い物が日用品にならないようにする。
        if let matched = bestMatch(in: merchant) {
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
        return result
    }

    /// 数字の並びから金額を拾う。
    ///
    /// レシートには金額と紛らわしい数字が多い。店番号 `SS-38125`、商品コード `0200`、
    /// 単価 `@155`、給油量 `19.12(L)`、カード番号の末尾 `XXXX6941`。
    /// どれも桁数だけでは金額と見分けがつかないので、前後に何が付いているかで落とす。
    private static func amounts(in line: String) -> [Int] {
        let normalized = normalizedDigits(line)
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<![-0-9A-Za-z@－])(?<![0-9]\.)([0-9]{1,7})(?![-0-9A-Za-z－])(?!\.[0-9])"#
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

    private static func looksLikeAddress(_ text: String) -> Bool {
        text.range(of: "[都道府県市区町村]|丁目|番地", options: .regularExpression) != nil
    }
}
