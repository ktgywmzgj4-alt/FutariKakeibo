import Foundation

/// 一度直した店の名前と種類を覚えておくための1件。
///
/// レシートの読み取りは店ごとの書式差に弱く、店名はロゴの読み違いで崩れる
/// （Selfixのレシートが「写北名古屋」になった）。そこで、**人が直した結果を覚えて
/// 次から使う**。行く店は限られているので、使うほど当たるようになる。
struct MerchantMemo: Identifiable, Codable, Hashable, Sendable {
    /// 同じ店だと見分けるための鍵。`MerchantKey` が作る。
    let key: String
    /// 人が確定させた店名。
    var merchant: String
    var category: ExpenseCategory
    var updatedAt: Date
    /// 同じ事業者だと見分けるための鍵（登録番号）。`MerchantKey.businessKey` が作る。
    ///
    /// 2026-10 より前に覚えた店には無い（`nil`）。古い版の端末と共有しても読めるよう、
    /// 無くてもよい項目にしてある。
    var businessKey: String?

    var id: String { key }

    init(
        key: String,
        merchant: String,
        category: ExpenseCategory,
        updatedAt: Date = .now,
        businessKey: String? = nil
    ) {
        self.key = key
        self.merchant = merchant
        self.category = category
        self.updatedAt = updatedAt
        self.businessKey = businessKey
    }
}

/// レシートから「同じ店かどうか」を見分ける鍵を作る。
///
/// 店名は読み違えるが、**電話番号は同じ店なら毎回同じ数字**になる。
/// 数字のほうが文字より正確に読めるので、そちらを優先する。
///
/// **インボイスの登録番号だけでは支店まで決めない。** 登録番号は事業者ごとの番号で、
/// イオンリテールのように1つの番号で全国の店を出している会社がある。登録番号で覚えると、
/// 別の支店のレシートに、前に行った支店の名前が入ってしまう。
enum MerchantKey {
    /// 覚えておく件数の上限。行く店はそう多くないので、これで足りる。
    static let limit = 300

    /// 店（支店）を見分ける鍵。
    ///
    /// 電話番号 → 登録番号＋店名 → 店名 の順。電話番号は店ごとに違うので支店まで見分けられる。
    static func make(fromReceiptText text: String, merchant: String) -> String? {
        let text = normalized(text)
        if let phone = storePhone(in: text) {
            return "tel:\(phone)"
        }
        let name = compacted(merchant)
        // 電話が読めなければ、登録番号に店名を添える。登録番号だけでは支店が分からない。
        if let number = invoiceNumber(in: text) {
            return name.isEmpty ? "invoice:\(number)" : "invoice:\(number)|\(name)"
        }
        // どちらも読めなければ店名。読み違いに弱いが、無いよりよい。
        return name.isEmpty ? nil : "name:\(name)"
    }

    /// 事業者を見分ける鍵（インボイスの登録番号）。支店の違いは見分けない。
    ///
    /// 2026-10 より前は、これを店の鍵にしていた。そのころ覚えた店の鍵はこの形をしている。
    static func businessKey(fromReceiptText text: String) -> String? {
        invoiceNumber(in: normalized(text)).map { "invoice:\($0)" }
    }

    /// インボイスの登録番号。T + 13桁。
    private static func invoiceNumber(in text: String) -> String? {
        firstMatch(#"[TtＴ]\s*([0-9]{13})"#, in: text)
    }

    /// 店の電話番号。
    ///
    /// フリーダイヤル（0120・0800）とナビダイヤル（0570）は会社全体の番号なので、店の見分けには使わない。
    private static func storePhone(in text: String) -> String? {
        for phone in allMatches(#"(0[0-9]{1,4}-[0-9]{1,4}-[0-9]{3,4})"#, in: text) {
            let digits = phone.filter(\.isNumber)
            if digits.hasPrefix("0120") || digits.hasPrefix("0800") || digits.hasPrefix("0570") {
                continue
            }
            return digits
        }
        return nil
    }

    /// 全角の数字と記号を半角に寄せる。数字の範囲だけを変換する。
    /// （文字列全体を変換するとカタカナまで半角になる。過去にそれで壊した）
    private static func normalized(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            let scalars = character.unicodeScalars
            if scalars.count == 1, let scalar = scalars.first {
                if scalar.value >= 0xFF10, scalar.value <= 0xFF19 {
                    result.append(Character(UnicodeScalar(UInt8(scalar.value - 0xFF10 + 48))))
                    continue
                }
                if scalar.value == 0xFF0D || scalar.value == 0x2010 || scalar.value == 0x2212 {
                    result.append("-")
                    continue
                }
            }
            result.append(character)
        }
        return result
    }

    /// 店名を鍵にするときの正規化。空白と記号の違いで別の店にならないようにする。
    private static func compacted(_ name: String) -> String {
        name.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation && !$0.isSymbol }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        allMatches(pattern, in: text).first
    }

    private static func allMatches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// 店名を比べるための形。`MerchantMemory` が「レシートにその店名が刷られているか」を見るのに使う。
    static func comparable(_ name: String) -> String {
        compacted(name)
    }
}

/// 覚えた店を引き当てて使う。
enum MerchantMemory {
    /// 覚えている店なら、店名と種類をそちらに差し替える。
    ///
    /// **人が直した結果が一番強い。** 読み取りの推測より優先する。
    ///
    /// 同じ店（電話番号など）として覚えていれば、店名も種類もそのまま使う。
    /// 同じ事業者（登録番号が同じ）としてしか分からないときは、**種類だけ**使う。
    /// 店名は、そのレシートにその店名が刷られているときだけ使う。
    /// チェーンの別の支店で、前に行った支店の名前を入れないため。
    static func applying(_ memos: [MerchantMemo], to draft: ReceiptDraft) -> ReceiptDraft {
        if let key = draft.shopKey, let memo = memos.first(where: { $0.key == key }) {
            var updated = draft
            updated.merchant = memo.merchant
            updated.suggestedCategory = memo.category
            updated.usedMemo = true
            return updated
        }

        // 2026-10 より前に覚えた店は、登録番号そのものが鍵になっている（`key == business`）。
        guard
            let business = draft.businessKey,
            let memo = memos
                .filter({ $0.businessKey == business || $0.key == business })
                .max(by: { $0.updatedAt < $1.updatedAt })
        else { return draft }

        var updated = draft
        updated.suggestedCategory = memo.category
        if receipt(draft.recognizedText, mentions: memo.merchant) {
            updated.merchant = memo.merchant
        }
        updated.usedMemo = true
        return updated
    }

    /// レシートの文字に、その店名がそのまま刷られているか。空白と記号の違いは見ない。
    private static func receipt(_ text: String, mentions merchant: String) -> Bool {
        let name = MerchantKey.comparable(merchant)
        guard name.count >= 2 else { return false }
        return MerchantKey.comparable(text).contains(name)
    }

    /// 保存されたときに覚える。すでに覚えている店なら上書きする。
    ///
    /// 覚え直せるようにしておかないと、一度間違って覚えた店を直せない。
    static func remembering(
        _ memos: [MerchantMemo],
        key: String,
        merchant: String,
        category: ExpenseCategory,
        businessKey: String? = nil,
        now: Date = .now
    ) -> [MerchantMemo] {
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !name.isEmpty else { return memos }

        var updated = memos.filter { $0.key != key }
        updated.append(
            MerchantMemo(key: key, merchant: name, category: category, updatedAt: now, businessKey: businessKey)
        )
        // 上限を超えたら、長く使っていないものから捨てる。
        guard updated.count > MerchantKey.limit else { return updated }
        return Array(updated.sorted { $0.updatedAt > $1.updatedAt }.prefix(MerchantKey.limit))
    }
}
