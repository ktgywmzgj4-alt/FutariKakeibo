import Foundation

/// レシートの読み取りで使う辞書（`Resources/ReceiptDictionary.json`）。
///
/// 店（チェーン）の名前と別名、品名の略し方、品の種類の手がかり。アプリに同梱し、
/// 端末の中だけで使う。**通信はしない。**
///
/// 読めなかったときは空の辞書になる。辞書を使わない読み方に戻るだけで、読み取りは止まらない。
///
/// 照らし合わせる語は、読み込むときに1回だけ照らし合わせる形（`ReceiptParser.dictionaryKey`）の
/// 文字の並び（`keyScalars`）にしておく。レシートの全部の行と見比べるので、そのたびに作り直さない。
struct ReceiptDictionary: Sendable {
    /// チェーンの店。別名は読み取りの崩れ方（ローマ字・略称）も含む。
    struct Chain: Equatable, Sendable {
        /// 画面に出す名前。
        var name: String
        var aliases: [String]
        var category: ExpenseCategory
        /// 照らし合わせる形（`ReceiptParser.dictionaryKey`）にした別名。
        var keys: [String]
        /// `keys` の1つずつを、文字の並びにしたもの。
        var keyScalars: [[Unicode.Scalar]]

        init(name: String, aliases: [String], category: ExpenseCategory, keys: [String]) {
            self.name = name
            self.aliases = aliases
            self.category = category
            self.keys = keys
            self.keyScalars = keys.map { Array($0.unicodeScalars) }
        }
    }

    /// 品名の略し方。**確かに同じものと言える略し方だけ**を置く。
    struct ProductName: Equatable, Sendable {
        var name: String
        var keys: [String]
        var keyScalars: [[Unicode.Scalar]]

        init(name: String, keys: [String]) {
            self.name = name
            self.keys = keys
            self.keyScalars = keys.map { Array($0.unicodeScalars) }
        }
    }

    /// 品の種類の手がかり。照らし合わせる形にした語。
    struct ProductCategory: Equatable, Sendable {
        var category: ExpenseCategory
        var keys: [String]
        var keyScalars: [[Unicode.Scalar]]

        init(category: ExpenseCategory, keys: [String]) {
            self.category = category
            self.keys = keys
            self.keyScalars = keys.map { Array($0.unicodeScalars) }
        }
    }

    var chains: [Chain]
    var productNames: [ProductName]
    var productCategories: [ProductCategory]

    static let empty = ReceiptDictionary(chains: [], productNames: [], productCategories: [])

    /// アプリに同梱した辞書。最初に使ったときに1回だけ読む。
    static let bundled: ReceiptDictionary = load()

    static func load(from bundle: Bundle? = nil) -> ReceiptDictionary {
        let bundle = bundle ?? Bundle(for: BundleToken.self)
        guard
            let url = bundle.url(forResource: "ReceiptDictionary", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return .empty }
        return decode(data) ?? .empty
    }

    /// JSON から作る。種類の名前が分からない項目は捨てる（1件の書き間違いで辞書全体を失わないため）。
    static func decode(_ data: Data) -> ReceiptDictionary? {
        guard let raw = try? JSONDecoder().decode(RawDictionary.self, from: data) else { return nil }
        let chains = raw.chains.compactMap { entry -> Chain? in
            guard let category = ExpenseCategory(rawValue: entry.category) else { return nil }
            let keys = entry.aliases.map(ReceiptParser.dictionaryKey).filter { $0.count >= 2 }
            guard !keys.isEmpty else { return nil }
            return Chain(name: entry.name, aliases: entry.aliases, category: category, keys: keys)
        }
        let products = raw.productNames.map { entry in
            ProductName(name: entry.name, keys: entry.aliases.map(ReceiptParser.dictionaryKey).filter { $0.count >= 2 })
        }
        // 種類の並びは固定する。同じ重さのときに、毎回同じ答えになるように。
        let order: [ExpenseCategory] = [.dining, .groceries, .household, .health, .beauty]
        let categories = order.compactMap { category -> ProductCategory? in
            guard let words = raw.productCategories[category.rawValue] else { return nil }
            return ProductCategory(
                category: category,
                keys: words.map(ReceiptParser.dictionaryKey).filter { !$0.isEmpty }
            )
        }
        return ReceiptDictionary(chains: chains, productNames: products, productCategories: categories)
    }

    private struct RawDictionary: Decodable {
        struct RawChain: Decodable {
            var name: String
            var aliases: [String]
            var category: String
        }
        struct RawProductName: Decodable {
            var name: String
            var aliases: [String]
        }
        var chains: [RawChain]
        var productNames: [RawProductName]
        var productCategories: [String: [String]]
    }
}

/// 辞書の入っている束を見つけるための目印。
private final class BundleToken {}
