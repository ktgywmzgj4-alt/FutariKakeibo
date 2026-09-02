import Foundation

enum CSVExporter {
    static func makeFile(
        expenses: [Expense],
        incomes: [Income] = [],
        household: Household
    ) throws -> URL {
        let header = "種別,日付,内容,金額,カテゴリ,相手,分け方,メモ\n"
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ja_JP")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // 支出と収入を日付順に混ぜて並べ、種別の列で見分けられるようにする。
        let expenseRows = expenses.map { expense in
            (
                date: expense.date,
                values: [
                    "支出",
                    dateFormatter.string(from: expense.date),
                    expense.title,
                    String(expense.amount),
                    expense.category.displayName,
                    household.member(id: expense.paidByMemberID)?.displayName ?? "不明",
                    expense.splitMethod.displayName,
                    expense.note
                ]
            )
        }
        let incomeRows = incomes.map { income in
            (
                date: income.date,
                values: [
                    "収入",
                    dateFormatter.string(from: income.date),
                    income.title,
                    String(income.amount),
                    income.source.displayName,
                    household.member(id: income.receivedByMemberID)?.displayName ?? "不明",
                    "",
                    income.note
                ]
            )
        }

        let rows = (expenseRows + incomeRows)
            .sorted { $0.date < $1.date }
            .map { $0.values.map(escape).joined(separator: ",") }
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
