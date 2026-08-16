import Foundation

enum ReceiptParser {
    private static let totalKeywords = ["合計", "総計", "お会計", "お支払", "grand total", "total"]
    private static let ignoredMerchantWords = ["領収書", "レシート", "receipt", "合計", "電話", "tel", "登録番号"]

    static func parse(text: String, now: Date = .now, calendar: Calendar = .current) -> ReceiptDraft {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return ReceiptDraft(
            merchant: merchant(from: lines),
            amount: totalAmount(from: lines),
            date: receiptDate(from: lines, now: now, calendar: calendar),
            suggestedCategory: category(from: text),
            recognizedText: text
        )
    }

    static func totalAmount(from lines: [String]) -> Int? {
        let prioritized = lines.filter { line in
            let lower = line.lowercased()
            return totalKeywords.contains { lower.contains($0) }
        }

        if let amount = prioritized.reversed().compactMap({ amounts(in: $0).max() }).first {
            return amount
        }

        return lines
            .flatMap(amounts(in:))
            .filter { $0 >= 1 && $0 <= 9_999_999 }
            .max()
    }

    static func merchant(from lines: [String]) -> String {
        for line in lines.prefix(8) {
            let lower = line.lowercased()
            let isIgnored = ignoredMerchantWords.contains { lower.contains($0) }
            let containsLetters = line.range(of: "[A-Za-zぁ-んァ-ヶ一-龠]", options: .regularExpression) != nil
            if !isIgnored && containsLetters && amounts(in: line).isEmpty && line.count <= 40 {
                return line
            }
        }
        return ""
    }

    static func category(from text: String) -> ExpenseCategory {
        let value = text.lowercased()
        let rules: [(ExpenseCategory, [String])] = [
            (.transportation, ["駅", "鉄道", "タクシー", "駐車", "高速", "ガソリン", "eneos"]),
            (.utilities, ["電気", "ガス", "水道", "通信", "携帯"]),
            (.health, ["病院", "医院", "薬局", "クリニック", "歯科"]),
            (.beauty, ["美容", "衣料", "服", "ユニクロ", "gu "]),
            (.travel, ["ホテル", "旅館", "宿泊", "レンタカー", "航空"]),
            (.dining, ["レストラン", "居酒屋", "カフェ", "ラーメン", "食堂", "coffee"]),
            (.household, ["ドラッグ", "ホームセンター", "日用品", "ダイソー"]),
            (.groceries, ["スーパー", "食品", "コンビニ", "market", "mart"]),
            (.entertainment, ["映画", "シネマ", "カラオケ", "チケット"])
        ]

        return rules.first { _, keywords in
            keywords.contains { value.contains($0) }
        }?.0 ?? .other
    }

    private static func amounts(in line: String) -> [Int] {
        let normalized = line
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")

        guard let regex = try? NSRegularExpression(pattern: #"(?<!\d)(\d{1,7})(?!\d)"#) else {
            return []
        }
        let range = NSRange(normalized.startIndex..., in: normalized)
        return regex.matches(in: normalized, range: range).compactMap { match in
            guard let swiftRange = Range(match.range(at: 1), in: normalized) else { return nil }
            return Int(normalized[swiftRange])
        }
    }

    private static func receiptDate(from lines: [String], now: Date, calendar: Calendar) -> Date? {
        let patterns = [
            #"(20\d{2})[年/.-](\d{1,2})[月/.-](\d{1,2})日?"#,
            #"(\d{1,2})[月/.-](\d{1,2})日?"#
        ]

        for line in lines {
            for (index, pattern) in patterns.enumerated() {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
                else { continue }

                let numbers = (1..<match.numberOfRanges).compactMap { group -> Int? in
                    guard let range = Range(match.range(at: group), in: line) else { return nil }
                    return Int(line[range])
                }

                let components: DateComponents
                if index == 0, numbers.count == 3 {
                    components = DateComponents(year: numbers[0], month: numbers[1], day: numbers[2])
                } else if index == 1, numbers.count == 2 {
                    components = DateComponents(
                        year: calendar.component(.year, from: now),
                        month: numbers[0],
                        day: numbers[1]
                    )
                } else {
                    continue
                }
                if let date = calendar.date(from: components) { return date }
            }
        }
        return nil
    }
}
