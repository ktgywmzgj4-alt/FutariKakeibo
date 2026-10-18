import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// レシートから「いつ・どこで・いくら・何の種類か」を決める。
///
/// まずルール（`ReceiptParser`）で読む。そのうえで、端末の中のAIが使えるなら
/// 同じ文字をAIにも読ませ、答えの取れた項目だけ差し替える。
///
/// AIが使えない端末でも、AIが答えられなくても、ルールの結果がそのまま残る。
/// **文字も画像も端末の外へは出ない。** 通信は一切しない。
enum ReceiptInterpreter {
    static func interpret(
        lines: [RecognizedLine],
        now: Date = .now,
        calendar: Calendar = .current,
        memos: [MerchantMemo] = []
    ) async -> ReceiptDraft {
        let base = ruleDraft(lines: lines, now: now, calendar: calendar, memos: memos)
        guard let answer = await OnDeviceReceiptReader.read(text: base.recognizedText) else {
            return base
        }
        return merged(base: base, answer: answer, now: now, calendar: calendar)
    }

    /// ルールだけで読んだ結果。
    ///
    /// 同じ店について覚えていることがあれば、それを使って読み直す。
    /// - レシートの書き方（`MerchantMemo.format`）: 前に合計だった行の書き方の行を、合計の語と同じに扱う
    /// - 人が直した品（`MerchantMemo.itemNotes`）: 同じ書き方の品に、直した名前と種類を付ける
    static func ruleDraft(
        lines: [RecognizedLine],
        now: Date = .now,
        calendar: Calendar = .current,
        memos: [MerchantMemo] = []
    ) -> ReceiptDraft {
        let draft = ReceiptParser.parse(lines: lines, now: now, calendar: calendar)
        let format = MerchantMemory.format(for: draft, in: memos)
        let notes = MerchantMemory.shopMemo(
            key: draft.shopKey,
            identifiers: draft.shopIdentifiers,
            in: memos
        )?.itemNotes ?? []
        guard format != nil || !notes.isEmpty else { return draft }
        return ReceiptParser.parse(lines: lines, now: now, calendar: calendar, format: format, itemNotes: notes)
    }

    /// AIの答えでルールの結果を上書きする。
    ///
    /// AIは自信が無くても何か答えてしまうことがあるので、明らかにおかしい値は捨てる。
    /// 捨てた項目はルールの結果が残るため、**AIを足したことで悪くなることはない。**
    static func merged(
        base: ReceiptDraft,
        answer: ReceiptAnswer,
        now: Date,
        calendar: Calendar
    ) -> ReceiptDraft {
        var draft = base

        let merchant = answer.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        // 「1点」のような数量、電話番号、日付は店名ではない。AIがそう答えても受け取らない。
        // 辞書のチェーンから組み立てた店名は動かさない（AIは支店名を落としたり崩したりする）。
        // 読めた品の名前も店名ではない（「◇ソーセージ（季節）1本」のような品の行を店名と答えることがある）。
        if !base.merchantIsWellEvidenced, ReceiptParser.isPlausibleMerchantName(merchant),
           !Self.isItemName(merchant, in: base.items) {
            draft.merchant = merchant
        }

        // AIの合計は、**読めた明細の和とつじつまが合うときだけ**受け取る。
        // 上限だけを見ていたので、コノミヤのレシートで 25 という答えがそのまま通り、
        // ルールが出した 3,374 を上書きしていた。これでは「AIを足したことで
        // 悪くなることはない」と言えない。
        //
        // さらに、明細が1件も読めないレシートでは照合する相手がいない。
        // イオンのレシートがそれで、カード会社の番号 47088 が素通りした。
        // **ルールが合計の語を手がかりに選べているなら、そちらを動かさない。**
        //
        // 小計＋外税、お預り−お釣りから合計が分かっているときは、**それと違う答えは受け取らない。**
        //
        // 税・小計・対象額の行にしか刷られていない金額も受け取らない（PISOLAの「10%課税額 659」）。
        if let total = answer.total, total > 0, total <= 9_999_999,
           !base.amountIsWellEvidenced || base.amount == nil,
           ReceiptParser.isConsistentWithItems(total, items: base.items),
           base.reconciledTotals.isEmpty || base.reconciledTotals.contains(total),
           !ReceiptParser.appearsOnlyOnSideRows(total, inReceiptText: base.recognizedText) {
            draft.amount = total
            // 足し算で確かめられた答えなら、確かめてもらう必要は無い。
            // それ以外は、AIの答えでも利用者に確かめてもらう（AIも外すので）。
            if base.reconciledTotals.contains(total) {
                draft.amountNeedsConfirmation = false
                draft.amountNote = nil
            }
        }

        // 未来の日付と、10年より前の日付は読み違い。レシートは過去のもの。
        if let parsed = answer.parsedDate(calendar: calendar) {
            let tenYearsAgo = calendar.date(byAdding: .year, value: -10, to: now) ?? .distantPast
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            if parsed >= tenYearsAgo, parsed <= tomorrow {
                draft.date = parsed
            }
        }

        // 店（外食など）や品の値段の重さで決めた種類は動かさない。AIが埋めるのは決めきれなかったときだけ。
        if !base.categoryIsWellEvidenced, let category = ExpenseCategory(rawValue: answer.category) {
            draft.suggestedCategory = category
        }

        return draft
    }

    /// 読めた品の名前と同じ（どちらかがもう一方を含む）か。照らし合わせる形で比べる。
    /// 3文字に満たない名前は比べない（「珈琲」のような短い品名が店名に含まれるのはふつう）。
    static func isItemName(_ text: String, in items: [ReceiptItem]) -> Bool {
        let key = ReceiptParser.dictionaryKey(text)
        guard key.count >= 3 else { return false }
        return items.contains { item in
            let itemKey = ReceiptParser.dictionaryKey(item.name)
            return itemKey.count >= 3 && (key.contains(itemKey) || itemKey.contains(key))
        }
    }
}

/// 端末の中のAIが返した4つの項目。
///
/// AIの実物から切り離してあるので、この形の組み立てと選別は
/// AIが動かない環境（CI）でも検査できる。
struct ReceiptAnswer: Equatable, Sendable {
    var date: String
    var merchant: String
    var total: Int?
    var category: String

    /// AIには決まった4行で答えさせる。表記の揺れをここで吸収する。
    ///
    ///     date: 2026-08-30
    ///     merchant: Selfix北名古屋
    ///     total: 2964
    ///     category: transportation
    static func parse(_ text: String) -> ReceiptAnswer? {
        var values: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<separator]
                .trimmingCharacters(in: CharacterSet(charactersIn: " -*\t"))
                .lowercased()
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, values[key] == nil else { continue }
            values[key] = value
        }
        guard !values.isEmpty else { return nil }

        let total = values["total"].flatMap { raw -> Int? in
            let digits = raw.filter(\.isNumber)
            return digits.isEmpty ? nil : Int(digits)
        }
        return ReceiptAnswer(
            date: values["date"] ?? "",
            merchant: values["merchant"] ?? "",
            total: total,
            category: (values["category"] ?? "").lowercased()
        )
    }

    /// `2026-08-30` の形を日付にする。区切りは `-` `/` `.` のどれでもよい。
    func parsedDate(calendar: Calendar) -> Date? {
        let numbers = date
            .components(separatedBy: CharacterSet(charactersIn: "-/. 年月日"))
            .compactMap { Int($0) }
        guard numbers.count >= 3 else { return nil }
        let (year, month, day) = (numbers[0], numbers[1], numbers[2])
        guard year >= 2000, year <= 2100, month >= 1, month <= 12, day >= 1, day <= 31 else {
            return nil
        }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

/// iPhoneの中で動くAppleのAIにレシートを読ませる。
///
/// iOS 26より前の端末、Apple Intelligenceが使えない端末では何もせず `nil` を返す。
/// 呼び出し側はルールの結果を使い続ける。
enum OnDeviceReceiptReader {
    static let instructions = """
    あなたは日本のレシートを読む係です。渡された文字はレシートを撮影して\
    文字認識にかけたものなので、誤字や余計な記号が混じっています。

    次の4つだけを答えてください。説明や前置きは書かないでください。

    date: 購入した日。YYYY-MM-DD の形式。読み取れなければ空欄。
    merchant: 店の名前。支店名まで含める。ロゴの読み違いは取り除く。読み取れなければ空欄。
    total: 支払った合計金額。数字だけ。円やカンマは書かない。読み取れなければ0。
    category: 次のうち1つだけ。groceries dining household transportation utilities \
    entertainment health beauty travel other

    合計を選ぶときの注意。店番号・伝票番号・端末番号・登録番号・カード番号・\
    承認番号は金額ではありません。単価や数量も合計ではありません。\
    「合計」「お買上」「ご請求」と書かれた金額を選んでください。

    categoryは買ったものから決めてください。ガソリンや駐車場はtransportation、\
    スーパーの食材はgroceries、飲食店はdining、洗剤や日用雑貨はhousehold、\
    薬や病院はhealth、電気ガス水道はutilitiesです。
    """

    static func read(text: String) async -> ReceiptAnswer? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: text)
                return ReceiptAnswer.parse(response.content)
            } catch {
                // AIが答えられなかっただけ。ルールの結果で続ける。
                return nil
            }
        }
        #endif
        return nil
    }
}
