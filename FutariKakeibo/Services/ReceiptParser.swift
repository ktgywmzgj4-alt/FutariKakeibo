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
        "合計", "小計", "総計", "お会計", "お支払", "消費税", "内税", "外税", "税額",
        "お預り", "お預かり", "お釣", "おつり", "釣銭", "現金", "クレジット", "電子マネー",
        "ポイント", "値引", "割引", "点数", "個数", "残高", "電話", "tel", "登録番号"
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
        var rows: [Row] = []
        for line in lines.sorted(by: { $0.midY < $1.midY }) {
            if let last = rows.last {
                let tolerance = max(max(last.height, line.height) * rowTolerance, 0.004)
                if abs(line.midY - last.midY) <= tolerance {
                    rows[rows.count - 1].fragments.append(line)
                    continue
                }
            }
            rows.append(Row(fragments: [line]))
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

        return ReceiptDraft(
            merchant: shopName,
            amount: totalAmount(from: rows),
            date: receiptDate(from: rows, now: now, calendar: calendar),
            items: items(from: rows, before: totalIndex),
            suggestedCategory: category(from: recognizedText, merchant: shopName),
            recognizedText: recognizedText
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

    static func merchant(from rows: [Row]) -> String {
        let candidates = rows.enumerated().filter { isMerchantCandidate($1) }
        guard !candidates.isEmpty else { return "" }

        // 店名はレシートの上の方に、他より大きな文字で刷られていることが多い。
        let upper = candidates.filter { $0.element.midY <= 0.45 }
        let pool = upper.isEmpty ? candidates : upper
        let tallest = pool.max { lhs, rhs in
            if lhs.element.height == rhs.element.height {
                return lhs.offset > rhs.offset
            }
            return lhs.element.height < rhs.element.height
        }
        return cleanedMerchant(tallest?.element.text ?? pool[0].element.text)
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
        // 数字ばかりの行は店名ではない。
        let digits = text.filter(\.isNumber).count
        return Double(digits) / Double(text.count) < 0.4
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

    static func totalAmount(from rows: [Row]) -> Int? {
        if let index = totalRowIndex(in: rows),
           let amount = amounts(in: rows[index].text).filter({ isPlausibleAmount($0) }).max() {
            return amount
        }
        // 合計の語が読めなかった場合は、金額らしい数字の最大値を使う。
        // 電話番号や日付の行は先に除いておく。
        let fallback = rows
            .filter { !looksLikePhoneNumber($0.text) && !looksLikeDate($0.text) }
            .flatMap { amounts(in: $0.text) }
            .filter { isPlausibleAmount($0) }
        return fallback.max()
    }

    static func totalAmount(from lines: [String]) -> Int? {
        totalAmount(from: rows(from: RecognizedLine.lines(fromPlainText: lines.joined(separator: "\n"))))
    }

    private static func isPlausibleAmount(_ value: Int) -> Bool {
        value >= 1 && value <= 9_999_999
    }

    // MARK: - 何を

    static func items(from rows: [Row], before totalIndex: Int?) -> [ReceiptItem] {
        let limit = totalIndex ?? rows.count
        var results: [ReceiptItem] = []

        for row in rows.prefix(limit) {
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

        let fragments = row.sortedFragments
        guard fragments.count >= 2 else { return itemFromSingleFragment(row) }

        // 一番右の断片が金額、その左が品名という並びを前提にする。
        guard
            let price = amounts(in: fragments[fragments.count - 1].text).last,
            isPlausibleAmount(price), price <= 999_999
        else { return nil }

        let name = cleanedItemName(fragments.dropLast().map(\.text).joined(separator: " "))
        guard isPlausibleItemName(name) else { return nil }
        return ReceiptItem(name: name, amount: price)
    }

    /// 品名と金額が1つの断片として読まれた場合。末尾の数字を金額として切り出す。
    private static func itemFromSingleFragment(_ row: Row) -> ReceiptItem? {
        let text = normalizedDigits(row.text)
        guard
            let match = text.range(of: #"([0-9]{1,6})\s*円?\s*[*※軽外内]?\s*$"#, options: .regularExpression)
        else { return nil }
        let priceText = text[match].filter(\.isNumber)
        guard let price = Int(priceText), isPlausibleAmount(price), price <= 999_999 else { return nil }

        let name = cleanedItemName(String(text[text.startIndex..<match.lowerBound]))
        guard isPlausibleItemName(name) else { return nil }
        return ReceiptItem(name: name, amount: price)
    }

    private static func cleanedItemName(_ text: String) -> String {
        text
            .trimmingCharacters(in: CharacterSet(charactersIn: " 　*※・|-–—軽外内"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func normalizedDigits(_ text: String) -> String {
        (text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
    }

    private static func amounts(in line: String) -> [Int] {
        let normalized = normalizedDigits(line)
        guard let regex = try? NSRegularExpression(pattern: #"(?<!\d)(\d{1,7})(?!\d)"#) else {
            return []
        }
        let range = NSRange(normalized.startIndex..., in: normalized)
        return regex.matches(in: normalized, range: range).compactMap { match in
            guard let swiftRange = Range(match.range(at: 1), in: normalized) else { return nil }
            return Int(normalized[swiftRange])
        }
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
