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

    var id: String { key }

    init(key: String, merchant: String, category: ExpenseCategory, updatedAt: Date = .now) {
        self.key = key
        self.merchant = merchant
        self.category = category
        self.updatedAt = updatedAt
    }
}

/// レシートから「同じ店かどうか」を見分ける鍵を作る。
///
/// 店名は読み違えるが、**登録番号と電話番号は同じ店なら毎回同じ数字**になる。
/// 数字のほうが文字より正確に読めるので、そちらを優先する。
enum MerchantKey {
    /// 覚えておく件数の上限。行く店はそう多くないので、これで足りる。
    static let limit = 300

    static func make(fromReceiptText text: String, merchant: String) -> String? {
        // インボイスの登録番号。T + 13桁。全国で店ごとに一意。
        if let number = firstMatch(#"[TtＴ]\s*([0-9]{13})"#, in: normalized(text)) {
            return "invoice:\(number)"
        }
        // 電話番号。店舗ごとに違う。
        if let phone = firstMatch(#"(0[0-9]{1,4}-[0-9]{1,4}-[0-9]{3,4})"#, in: normalized(text)) {
            return "tel:\(phone.filter(\.isNumber))"
        }
        // どちらも読めなければ店名。読み違いに弱いが、無いよりよい。
        let name = compacted(merchant)
        return name.isEmpty ? nil : "name:\(name)"
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
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard
            let match = regex.firstMatch(in: text, range: range),
            let captured = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[captured])
    }
}

/// 覚えた店を引き当てて使う。
enum MerchantMemory {
    /// 覚えている店なら、店名と種類をそちらに差し替える。
    ///
    /// **人が直した結果が一番強い。** 読み取りの推測より優先する。
    static func applying(_ memos: [MerchantMemo], to draft: ReceiptDraft) -> ReceiptDraft {
        guard
            let key = draft.shopKey,
            let memo = memos.first(where: { $0.key == key })
        else { return draft }

        var updated = draft
        updated.merchant = memo.merchant
        updated.suggestedCategory = memo.category
        updated.usedMemo = true
        return updated
    }

    /// 保存されたときに覚える。すでに覚えている店なら上書きする。
    ///
    /// 覚え直せるようにしておかないと、一度間違って覚えた店を直せない。
    static func remembering(
        _ memos: [MerchantMemo],
        key: String,
        merchant: String,
        category: ExpenseCategory,
        now: Date = .now
    ) -> [MerchantMemo] {
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !name.isEmpty else { return memos }

        var updated = memos.filter { $0.key != key }
        updated.append(
            MerchantMemo(key: key, merchant: name, category: category, updatedAt: now)
        )
        // 上限を超えたら、長く使っていないものから捨てる。
        guard updated.count > MerchantKey.limit else { return updated }
        return Array(updated.sorted { $0.updatedAt > $1.updatedAt }.prefix(MerchantKey.limit))
    }
}
