import Foundation

enum CSVExporter {
    static func makeFile(expenses: [Expense], household: Household) throws -> URL {
        let header = "日付,内容,金額,カテゴリ,支払った人,分け方,メモ\n"
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ja_JP")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let rows = expenses
            .sorted { $0.date < $1.date }
            .map { expense in
                let payer = household.member(id: expense.paidByMemberID)?.displayName ?? "不明"
                return [
                    dateFormatter.string(from: expense.date),
                    expense.title,
                    String(expense.amount),
                    expense.category.displayName,
                    payer,
                    expense.splitMethod.displayName,
                    expense.note
                ].map(escape).joined(separator: ",")
            }
            .joined(separator: "\n")

        let csv = "\u{FEFF}" + header + rows + "\n"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ふたり家計簿-\(ISO8601DateFormatter().string(from: .now)).csv")
        let data = Data(csv.utf8)
        try data.write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        return url
    }

    private static func escape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
