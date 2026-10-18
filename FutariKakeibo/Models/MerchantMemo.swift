import Foundation

/// 一度直した店の名前と種類を覚えておくための1件。
///
/// レシートの読み取りは店ごとの書式差に弱く、店名はロゴの読み違いで崩れる
/// （Selfixのレシートが「写北名古屋」になった）。そこで、**人が直した結果を覚えて
/// 次から使う**。行く店は限られているので、使うほど当たるようになる。
///
/// **一度保存されただけでは、確かな店としない**（2026-10）。読み違いに気づかずに保存されたのかも
/// しれない。人が店名か種類を直して保存したら、その1回で確かな店にする。直さずに保存されたものは、
/// 同じ店名と種類で2回保存されたら確かな店にする（`isTrusted`）。確かでない店は、読み取りに
/// 確かな手がかりが無いところ（辞書に無い店名、決めきれなかった種類）だけを埋める。
///
/// 増えた項目はどれも無くてもよい（`nil`）。古い版の端末と共有しても読めるように。
/// CloudKit には今までどおり `merchantMemosData` の1つの項目として入るので、項目は増えない。
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
    /// 人が店名か種類を、読み取った内容から直して保存したか。
    ///
    /// 2026-10 より前に覚えた店には無い（`nil`）。それまでは保存のたびに確かな店として使っていたので、
    /// 無いものは確かな店として扱う（覚えた店の効き方を変えない）。
    var corrected: Bool?
    /// 直さずに、同じ店名と種類のまま保存された回数。
    var confirmations: Int?
    /// この店を見分けた鍵（電話番号、登録番号＋店名、店名）。`key` のほかに読めたもの。
    /// 電話番号が読めた日と読めなかった日で鍵が変わっても、同じ店と分かるように覚える。
    var identifiers: [String]?
    /// この店のレシートの書き方（合計の行の書き方）。
    var format: ReceiptFormat?
    /// 品から決まった種類を、この店で人が直した先（読み取りの種類の `rawValue` → 保存した種類）。
    ///
    /// 品から決まった種類は、覚えた店の種類では上書きしない。ただし人が直したことは覚える
    /// （ドラッグストアの食べ物も「医療・健康」に付ける、のような家ごとの付け方）。
    /// **品の名前は残さない。** 種類の組だけ。
    var categoryCorrections: [String: ExpenseCategory]?
    /// この店での品の書き方と、人が直した名前・種類（`ItemNote`）。新しいものが先。
    ///
    /// 人が読み取った品の一覧で直した品だけ（2026-10-18 利用者が決定）。金額・日付・
    /// どのレシートの品かは残さない。
    var itemNotes: [ItemNote]?

    var id: String { key }

    init(
        key: String,
        merchant: String,
        category: ExpenseCategory,
        updatedAt: Date = .now,
        businessKey: String? = nil,
        corrected: Bool? = nil,
        confirmations: Int? = nil,
        identifiers: [String]? = nil,
        format: ReceiptFormat? = nil,
        categoryCorrections: [String: ExpenseCategory]? = nil,
        itemNotes: [ItemNote]? = nil
    ) {
        self.key = key
        self.merchant = merchant
        self.category = category
        self.updatedAt = updatedAt
        self.businessKey = businessKey
        self.corrected = corrected
        self.confirmations = confirmations
        self.identifiers = identifiers
        self.format = format
        self.categoryCorrections = categoryCorrections
        self.itemNotes = itemNotes
    }

    /// 読み取りの推測より優先してよい店か。人が直したか、直さずに同じ内容で2回保存されたか。
    var isTrusted: Bool {
        corrected != false || (confirmations ?? 0) >= MerchantMemory.confirmationsToTrust
    }

    /// 見分けに使う鍵の全部（`key` と `identifiers`）。
    var allIdentifiers: [String] {
        [key] + (identifiers ?? []).filter { $0 != key }
    }
}

/// 店ごとのレシートの書き方。同じ店のレシートは、同じ書式で刷られる。
///
/// いま覚えるのは**合計の行の書き方**だけ。読み取りの語の一覧に無い書き方（「お買物額」）の店や、
/// 「合計」がいつも「合言十」と読まれる店で、合計の行を見つけられるように
/// （同じ店の同じ印字は、同じように読み違えることが多い）。
struct ReceiptFormat: Codable, Hashable, Sendable {
    /// 合計の行の、数字と記号を除いた文字（`ReceiptParser.rowLabel` の形）。
    var totalLabel: String
    /// 人が合計を直して保存した1枚から覚えたか。
    var corrected: Bool
    /// この書き方の行の金額で保存された回数。
    var seen: Int

    /// 読み取りに使ってよいか。人が合計を直した1回か、直さずに同じ書き方を2回見たら。
    var isTrusted: Bool {
        corrected || seen >= MerchantMemory.confirmationsToTrust
    }
}

/// この店での品の書き方と、人が直した名前・種類。
///
/// 同じ店のレシートは、同じ品を同じ書き方で刷る（「ボールドJ」）。人が一度直せば、
/// 次からその書き方の品は最初から直した名前と種類になる。**人が直した品だけ**を覚え、
/// 金額・日付・どのレシートの品かは残さない。
struct ItemNote: Codable, Hashable, Sendable {
    /// 品の書き方を照らし合わせる形にしたもの（`ReceiptParser.dictionaryKey`）。
    var key: String
    /// 読み取った書き方。一覧に出すため。
    var text: String
    /// 人が付けた名前。付けていなければ nil。
    var name: String?
    /// 人が選んだ種類。選んでいなければ nil。
    var category: ExpenseCategory?
    var updatedAt: Date
}

/// 保存された1枚から、店について覚えること。
struct MerchantObservation: Equatable, Sendable {
    /// その1枚で読めた店の鍵（`MerchantKey.make`）。
    var key: String
    /// 鍵のほかに読めた見分けの鍵（`MerchantKey.identifiers`）。
    var identifiers: [String] = []
    var merchant: String
    var category: ExpenseCategory
    /// 人が店名か種類を、画面に出した内容から直して保存したか。
    var corrected: Bool
    var businessKey: String?
    /// 保存された合計が刷られていた行の書き方（`ReceiptParser.totalLabel`）。
    var totalLabel: String?
    /// 人が合計を、読み取った金額から直して保存したか。
    var totalCorrected = false
    /// 読み取りが出した種類（覚えた店を当てはめる前）と、それが品の値段の重さで決まったか。
    var readCategory: ExpenseCategory?
    var readCategoryByItems = false
    /// 人が読み取った品の一覧で直した品。
    var itemNotes: [ItemNote] = []
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

    /// その1枚で読めた、支店まで見分けられる鍵の全部（電話番号と、登録番号＋店名）。
    ///
    /// `make` は1つしか返さないので、電話番号が読めた日と読めなかった日で鍵が変わる。
    /// 覚えるときにこれを全部覚えておけば、次にどちらか1つが読めれば同じ店と分かる。
    /// 登録番号だけ（店名の無いもの）は事業者の鍵なので入れない。どちらも無ければ店名の鍵。
    static func identifiers(fromReceiptText text: String, merchant: String) -> [String] {
        let text = normalized(text)
        let name = compacted(merchant)
        var keys: [String] = []
        if let phone = storePhone(in: text) { keys.append("tel:\(phone)") }
        if let number = invoiceNumber(in: text), !name.isEmpty { keys.append("invoice:\(number)|\(name)") }
        if keys.isEmpty, !name.isEmpty { keys.append("name:\(name)") }
        return keys
    }

    /// 電話番号から作った鍵か。電話番号は支店ごとに違う。
    static func isPhoneKey(_ key: String) -> Bool {
        key.hasPrefix("tel:")
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
    /// 直さずに保存された店（と合計の行の書き方）を、確かとみなすまでの回数。
    static let confirmationsToTrust = 2
    /// 1つの店で覚えておく見分けの鍵の数。
    static let identifierLimit = 6
    /// 1つの店で覚えておく品の数。
    static let itemNoteLimit = 20
    /// 全部の店で覚えておく品の数。覚えた店は家計簿の1件（CloudKit の1レコード）に入るので、大きくしない。
    static let totalItemNoteLimit = 600

    /// 覚えている店なら、店名と種類をそちらに差し替える。
    ///
    /// **人が直した結果が一番強い。** 確かな店（`MerchantMemo.isTrusted`）は読み取りの推測より優先する。
    /// 確かでない店は、読み取りに確かな手がかりが無いところだけを埋める。
    ///
    /// **品から決まった種類は動かさない。** 同じ店でも、買った物で種類は変わる
    /// （スーパーで洗剤だけ買った日は日用品）。店名は店を見分けるのに、品名は種類を決めるのに使う。
    ///
    /// 同じ店（電話番号など）として覚えていれば、店名も種類も使う。
    /// 同じ事業者（登録番号が同じ）としてしか分からないときは、**種類だけ**使う。
    /// 店名は、そのレシートにその店名が刷られているときだけ使う。
    /// チェーンの別の支店で、前に行った支店の名前を入れないため。
    static func applying(_ memos: [MerchantMemo], to draft: ReceiptDraft) -> ReceiptDraft {
        if let memo = shopMemo(key: draft.shopKey, identifiers: draft.shopIdentifiers, in: memos) {
            var updated = draft
            if memo.isTrusted || !draft.merchantIsWellEvidenced || draft.merchant.isEmpty {
                updated.merchant = memo.merchant
            }
            if draft.categoryDecidedByItems,
               let corrected = memo.categoryCorrections?[draft.suggestedCategory.rawValue] {
                // 品から決まった種類を、この店で人が直した先。
                updated.suggestedCategory = corrected
            } else if takesCategory(from: memo, for: draft) {
                updated.suggestedCategory = memo.category
            }
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
        if takesCategory(from: memo, for: draft) {
            updated.suggestedCategory = memo.category
        }
        if receipt(draft.recognizedText, mentions: memo.merchant) {
            updated.merchant = memo.merchant
        }
        updated.usedMemo = true
        return updated
    }

    /// 覚えた種類を使うか。品から決まった種類は使わない。確かでない店の種類は、手がかりの弱いときだけ。
    private static func takesCategory(from memo: MerchantMemo, for draft: ReceiptDraft) -> Bool {
        guard !draft.categoryDecidedByItems else { return false }
        return memo.isTrusted || !draft.categoryIsWellEvidenced
    }

    /// この店（支店）として覚えている1件。
    ///
    /// 鍵が同じものを先に見る。無ければ、前に同じ店で読めた鍵（電話番号、登録番号＋店名）の
    /// どれかが同じもの。ただし電話番号が両方にあって違うなら、同じ会社の別の支店なので使わない。
    static func shopMemo(key: String?, identifiers: [String], in memos: [MerchantMemo]) -> MerchantMemo? {
        if let key, let memo = memos.first(where: { $0.key == key }) { return memo }
        let seen = identifiers + (key.map { [$0] } ?? [])
        guard !seen.isEmpty else { return nil }
        let phone = seen.first(where: MerchantKey.isPhoneKey)
        return memos
            .filter { memo in
                let known = memo.allIdentifiers
                guard known.contains(where: { seen.contains($0) }) else { return false }
                if let phone, let other = known.first(where: MerchantKey.isPhoneKey), other != phone {
                    return false
                }
                return true
            }
            .max { $0.updatedAt < $1.updatedAt }
    }

    /// 同じ店のレシートの書き方を覚えていれば、それ。確かなもの（`ReceiptFormat.isTrusted`）だけ。
    static func format(for draft: ReceiptDraft, in memos: [MerchantMemo]) -> ReceiptFormat? {
        guard
            let format = shopMemo(key: draft.shopKey, identifiers: draft.shopIdentifiers, in: memos)?.format,
            format.isTrusted
        else { return nil }
        return format
    }

    /// レシートの文字に、その店名がそのまま刷られているか。空白と記号の違いは見ない。
    private static func receipt(_ text: String, mentions merchant: String) -> Bool {
        let name = MerchantKey.comparable(merchant)
        guard name.count >= 2 else { return false }
        return MerchantKey.comparable(text).contains(name)
    }

    /// 保存された1枚から覚える。
    ///
    /// - 人が店名か種類を直していたら、その内容で覚え直す（確かな店になる）
    /// - 直さずに保存されたら、覚えている内容と同じなら回数を数える（2回で確かな店になる）。
    ///   違えば、確かな店はそのまま残し（読み取りの推測で上書きしない）、確かでない店は覚え直す
    /// - どの場合も、この店を見分けた鍵と、合計の行の書き方を足す
    ///
    /// 覚え直せるようにしておかないと、一度間違って覚えた店を直せない。
    static func remembering(
        _ memos: [MerchantMemo],
        _ observation: MerchantObservation,
        now: Date = .now
    ) -> [MerchantMemo] {
        let name = observation.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !observation.key.isEmpty, !name.isEmpty else { return memos }

        let existing = shopMemo(key: observation.key, identifiers: observation.identifiers, in: memos)
        let sameContent = existing.map {
            MerchantKey.comparable($0.merchant) == MerchantKey.comparable(name) && $0.category == observation.category
        } ?? false

        var memo: MerchantMemo
        if observation.corrected {
            memo = MerchantMemo(
                key: observation.key,
                merchant: name,
                category: observation.category,
                corrected: true,
                confirmations: 1
            )
        } else if let existing, sameContent {
            memo = existing
            memo.confirmations = (existing.confirmations ?? 1) + 1
        } else if let existing, existing.isTrusted {
            // 確かな店は、確かめていない読み取りで上書きしない。見分けの鍵だけ足す。
            memo = existing
        } else {
            memo = MerchantMemo(
                key: observation.key,
                merchant: name,
                category: observation.category,
                corrected: false,
                confirmations: 1
            )
        }
        memo.updatedAt = now
        memo.businessKey = observation.businessKey ?? existing?.businessKey
        memo.identifiers = mergedIdentifiers(existing: existing, observation: observation, key: memo.key)
        memo.format = learnedFormat(existing?.format, from: observation)
        memo.categoryCorrections = learnedCategoryCorrections(existing?.categoryCorrections, from: observation)
        memo.itemNotes = mergedItemNotes(existing?.itemNotes, observation.itemNotes)

        var updated = memos.filter { $0.key != memo.key && $0.key != existing?.key }
        updated.append(memo)
        // 上限を超えたら、長く使っていないものから捨てる。
        if updated.count > MerchantKey.limit {
            updated = Array(updated.sorted { $0.updatedAt > $1.updatedAt }.prefix(MerchantKey.limit))
        }
        return trimmedItemNotes(updated)
    }

    /// 人が確かめた店名と種類で覚える（`MerchantObservation.corrected` が立った形）。
    static func remembering(
        _ memos: [MerchantMemo],
        key: String,
        merchant: String,
        category: ExpenseCategory,
        businessKey: String? = nil,
        now: Date = .now
    ) -> [MerchantMemo] {
        remembering(
            memos,
            MerchantObservation(
                key: key,
                merchant: merchant,
                category: category,
                corrected: true,
                businessKey: businessKey
            ),
            now: now
        )
    }

    /// 覚えている店の一覧で名前を直す。人が直したので、確かな店になる。
    ///
    /// **鍵（`key`）は変えない。** 鍵は登録番号や電話番号から作られていて、
    /// 同じ店かどうかを見分けているのはそちら。名前だけが人の読むもの。
    static func renaming(
        _ memos: [MerchantMemo],
        key: String,
        to merchant: String,
        now: Date = .now
    ) -> [MerchantMemo] {
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = memos.firstIndex(where: { $0.key == key }) else { return memos }
        guard memos[index].merchant != name || memos[index].corrected == false else { return memos }
        var updated = memos
        updated[index].merchant = name
        updated[index].corrected = true
        updated[index].updatedAt = now
        return updated
    }

    /// 覚えている店の一覧から、覚えた品の1件を忘れる（間違って直した品を消せるように）。
    static func forgettingItemNote(_ memos: [MerchantMemo], shopKey: String, noteKey: String) -> [MerchantMemo] {
        guard let index = memos.firstIndex(where: { $0.key == shopKey }),
              let notes = memos[index].itemNotes, notes.contains(where: { $0.key == noteKey })
        else { return memos }
        var updated = memos
        let kept = notes.filter { $0.key != noteKey }
        updated[index].itemNotes = kept.isEmpty ? nil : kept
        return updated
    }

    /// 品の直しを足す。同じ書き方の品は新しい直しで置き換え、新しいものを先に `itemNoteLimit` 件まで。
    private static func mergedItemNotes(_ existing: [ItemNote]?, _ added: [ItemNote]) -> [ItemNote]? {
        let fresh = added.filter { !$0.key.isEmpty && ($0.name != nil || $0.category != nil) }
        var merged: [ItemNote] = []
        for note in fresh + (existing ?? []) where !merged.contains(where: { $0.key == note.key }) {
            merged.append(note)
        }
        let kept = Array(merged.prefix(itemNoteLimit))
        return kept.isEmpty ? nil : kept
    }

    /// 全部の店の品の直しが `totalItemNoteLimit` 件を超えたら、古いものから捨てる。
    private static func trimmedItemNotes(_ memos: [MerchantMemo]) -> [MerchantMemo] {
        let all = memos.flatMap { $0.itemNotes ?? [] }
        guard all.count > totalItemNoteLimit else { return memos }
        let cutoff = all.map(\.updatedAt).sorted(by: >)[totalItemNoteLimit - 1]
        var budget = totalItemNoteLimit
        return memos.map { memo in
            guard let notes = memo.itemNotes else { return memo }
            var trimmed = memo
            let kept = notes.filter { note in
                // 境目と同じ時刻のものは、数の上限に収まるぶんだけ残す。
                guard note.updatedAt >= cutoff, budget > 0 else { return false }
                budget -= 1
                return true
            }
            trimmed.itemNotes = kept.isEmpty ? nil : kept
            return trimmed
        }
    }

    /// 前に読めた鍵と、この1枚で読めた鍵。新しいものを先に、`identifierLimit` 個まで。
    /// 登録番号だけの鍵（事業者の鍵）は支店を見分けないので入れない。
    private static func mergedIdentifiers(
        existing: MerchantMemo?,
        observation: MerchantObservation,
        key: String
    ) -> [String]? {
        let business = [observation.businessKey, existing?.businessKey].compactMap { $0 }
        var merged: [String] = []
        for identifier in [observation.key] + observation.identifiers + (existing?.allIdentifiers ?? [])
        where !identifier.isEmpty && identifier != key && !business.contains(identifier) && !merged.contains(identifier) {
            merged.append(identifier)
        }
        let kept = Array(merged.prefix(identifierLimit))
        return kept.isEmpty ? nil : kept
    }

    /// 品から決まった種類を、人が直した先を覚える。保存した種類が読み取りと違うときだけ
    /// （違うのは、人が直したか、前に直した先を当てはめたとき）。読み取りどおりに保存されたら、
    /// その種類の直し先は忘れる（人が元に戻した）。
    private static func learnedCategoryCorrections(
        _ existing: [String: ExpenseCategory]?,
        from observation: MerchantObservation
    ) -> [String: ExpenseCategory]? {
        guard observation.readCategoryByItems, let read = observation.readCategory else { return existing }
        var corrections = existing ?? [:]
        corrections[read.rawValue] = observation.category == read ? nil : observation.category
        return corrections.isEmpty ? nil : corrections
    }

    /// 合計の行の書き方を覚える。人が合計を直した1枚から覚えたものは、その1回で確かとする。
    /// 直さずに保存された1枚からは、同じ書き方を数える。確かな書き方は、確かめていない1枚で置き換えない。
    private static func learnedFormat(_ existing: ReceiptFormat?, from observation: MerchantObservation) -> ReceiptFormat? {
        guard let label = observation.totalLabel, !label.isEmpty else { return existing }
        if observation.totalCorrected {
            return ReceiptFormat(totalLabel: label, corrected: true, seen: 1)
        }
        guard let existing else { return ReceiptFormat(totalLabel: label, corrected: false, seen: 1) }
        if existing.totalLabel == label {
            var updated = existing
            updated.seen += 1
            return updated
        }
        return existing.isTrusted ? existing : ReceiptFormat(totalLabel: label, corrected: false, seen: 1)
    }
}
