import Foundation

/// レシート画像から読み取った文字の断片と、その位置。
/// 位置を保つことで「品名は左、金額は右」「店名は大きい」といった
/// レシート特有の手がかりを解析に使える。
struct RecognizedLine: Equatable, Sendable {
    var text: String
    /// 画像の左端が0、右端が1。
    var minX: Double
    var maxX: Double
    /// 画像の上端が0、下端が1。
    var midY: Double
    /// 文字の高さ。画像の高さに対する割合。店名は他より大きく写ることが多い。
    var height: Double

    init(
        text: String,
        minX: Double = 0,
        maxX: Double = 1,
        midY: Double = 0,
        height: Double = 0.02
    ) {
        self.text = text
        self.minX = minX
        self.maxX = maxX
        self.midY = midY
        self.height = height
    }

    /// 位置の分からない文字列（貼り付けたテキストやテスト）から作る。
    static func lines(fromPlainText text: String) -> [RecognizedLine] {
        let rows = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let step = rows.isEmpty ? 0 : 1.0 / Double(rows.count + 1)
        return rows.enumerated().map { index, row in
            RecognizedLine(text: row, midY: step * Double(index + 1))
        }
    }
}

/// レシートから読み取った明細の1行。
struct ReceiptItem: Equatable, Identifiable, Sendable {
    var name: String
    var amount: Int

    var id: String { "\(name)-\(amount)" }
}
