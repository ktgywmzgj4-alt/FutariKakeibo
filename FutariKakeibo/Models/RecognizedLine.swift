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
    /// この断片の傾き。左端から右端へ1進むあいだに `midY` がどれだけ増えるか。
    ///
    /// 斜めから撮ると、同じ行でも右へ行くほど上（または下）へずれる。
    /// 読み取りは文字の四隅を返すので、行の傾きをここに直接測って入れられる。
    /// 正面から撮った写真と、位置の分からない文字列では 0。
    var slope: Double
    /// 読み取りが2番目、3番目に考えた読み方。いちばん確からしいものが `text`。
    ///
    /// 「¥3,374」を「¥3,874」と読んだとき、正しい読み方がここに残っていることがある。
    /// **ここから選び直すのは、金額の足し算が合うといった、より強い根拠があるときだけ**
    /// （`ReceiptParser.totalCandidates`）。
    var alternatives: [String]
    /// `text` の確からしさ（0〜1）。位置の分からない文字列やテストでは 1。
    var confidence: Double

    /// 断片の中央の横位置。傾きぶんを戻すときの基準になる。
    var midX: Double { (minX + maxX) / 2 }

    init(
        text: String,
        minX: Double = 0,
        maxX: Double = 1,
        midY: Double = 0,
        height: Double = 0.02,
        slope: Double = 0,
        alternatives: [String] = [],
        confidence: Double = 1
    ) {
        self.text = text
        self.minX = minX
        self.maxX = maxX
        self.midY = midY
        self.height = height
        self.slope = slope
        self.alternatives = alternatives
        self.confidence = confidence
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
///
/// **記録はしない。** 種類を推し量る手がかりと、合計のつじつまを確かめるためだけに使う。
struct ReceiptItem: Equatable, Identifiable, Sendable {
    var name: String
    /// その行に刷られた値段。値引きの前。
    var amount: Int
    /// 数量。「(2個 X 単58)」のような行があったときだけ入る。
    var quantity: Int?
    /// 単価。数量と一緒に入る。
    var unitPrice: Int?
    /// この品に付いた値引き（正の数）。「割引 20% -56」なら 56。
    var discount: Int

    init(name: String, amount: Int, quantity: Int? = nil, unitPrice: Int? = nil, discount: Int = 0) {
        self.name = name
        self.amount = amount
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.discount = discount
    }

    /// 値引きのあとの値段。
    var netAmount: Int { amount - discount }

    var id: String { "\(name)-\(amount)" }
}
