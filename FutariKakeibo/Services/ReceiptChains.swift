import Foundation

/// 店名を、辞書（`ReceiptDictionary`）のチェーンと照らし合わせて組み立て直す。
///
/// 店名はロゴの崩れや略し方で外れる（「AEON STYLE」「mister Donut」「エクポスタイル」）。
/// チェーンの名前が分かれば、店名は「チェーン名 支店名」にできる。
///
/// **支店は登録番号では決めない**（事業者ごとの番号だから）。支店名はレシートに刷られた
/// 文字（「城町店」「ワンダーシティ」「mozoワンダーシティショップ」）からだけ取る。
/// 見つからなければチェーン名だけにする。支店名を作ることはしない。
extension ReceiptParser {
    /// 辞書と照らし合わせる形。互換文字をそろえ（全角英数→半角、半角カナ→全角）、
    /// ひらがなをカタカナに、小文字にして、文字と数字以外を落とす。
    static func dictionaryKey(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for character in text {
            forEachKeyScalar(of: character) { scalars.append($0) }
        }
        return String(scalars)
    }

    /// 1文字を照らし合わせる形にした文字（0個以上）を、順に `body` へ渡す。
    ///
    /// レシートの全部の行に使うので速さが要る。よく出る文字（半角英数・かな・漢字）はここで
    /// 直接変換し、それ以外（全角英数・半角カナ・記号）だけ互換分解に通す。
    /// 1文字ごとに文字の変換（ICU）を呼んでいたときは、長いレシートの解析が倍近く遅くなった。
    private static func forEachKeyScalar(of character: Character, _ body: (Unicode.Scalar) -> Void) {
        let units = character.unicodeScalars
        if units.count == 1, let scalar = units.first {
            switch scalar.value {
            case 0x30...0x39, 0x61...0x7A:
                body(scalar)
                return
            case 0x41...0x5A:
                // 英大文字は小文字に。
                if let lower = Unicode.Scalar(scalar.value + 0x20) { body(lower) }
                return
            case 0x00...0x7F:
                // そのほかの半角の記号と空白は落とす。
                return
            case 0x3041...0x3096:
                // ひらがなはカタカナに。
                if let katakana = Unicode.Scalar(scalar.value + 0x60) { body(katakana) }
                return
            case 0x30A1...0x30FA, 0x30FC...0x30FE, 0x4E00...0x9FFF:
                // カタカナ・長音・漢字はそのまま。
                body(scalar)
                return
            default:
                break
            }
        }
        let folded = String(character).precomposedStringWithCompatibilityMapping.lowercased()
        for scalar in folded.unicodeScalars {
            let value = (0x3041...0x3096).contains(scalar.value) ? Unicode.Scalar(scalar.value + 0x60) ?? scalar : scalar
            if CharacterSet.alphanumerics.contains(value) { body(value) }
        }
    }

    /// 辞書で見つけたチェーンと、その名前が刷られていた行。
    struct ChainMatch: Equatable, Sendable {
        var chain: ReceiptDictionary.Chain
        var rowIndex: Int
        /// 名前が見つかった文字（行の文字、または読み取りの別の読み方）。
        var text: String
        /// チェーンの名前のあとに続く文字（支店名の候補）。
        var suffix: String
        /// 名前と支店名のあいだに空きが無いか（「イオンスタイルワンダーシティ」「Selfix北名古屋」）。
        var attached: Bool
        /// 1文字の読み違いを許して見つけたか。
        var fuzzy: Bool
    }

    /// 1文字の読み違いまで許す別名の長さ。短い名前で許すと別の語に当たる。
    private static let fuzzyAliasMinimumLength = 5
    /// 支店名を探す上の行の数。
    private static let branchSearchRows = 10
    /// 支店名の終わりに付く語。
    private static let shopWords = ["店", "ショップ", "shop", "支店", "号店", "売店"]

    /// 店名を組み立て直す。チェーンが見つからなければ nil（今までの選び方に任せる）。
    static func chainMerchant(
        in rows: [Row],
        dictionary: ReceiptDictionary
    ) -> (name: String, chain: ReceiptDictionary.Chain)? {
        let matches = chainMatches(in: rows, dictionary: dictionary)
        guard let chain = matches.first?.chain else { return nil }
        let own = matches.filter { $0.chain == chain && !isCompanyLine(rows[$0.rowIndex].text) }

        // 1. チェーン名と支店名が1行に刷られている（「マクドナルド城町店」「コノミヤ 城西店」）。
        //    支店名が「店」で終わるか、いちばん上の数行にあるときだけ（下の広告の行は使わない）。
        let branched = own.compactMap { match -> (match: ChainMatch, branch: String)? in
            let branch = cleanedBranch(match.suffix, chain: chain)
            guard isPlausibleBranch(branch) else { return nil }
            guard endsWithShopWord(branch) || match.rowIndex < 3 else { return nil }
            return (match, branch)
        }
        if let best = branched.first(where: { endsWithShopWord($0.branch) }) ?? branched.first {
            // 刷られたとおりに出す。名前を読み違えていた（1文字違いで見つけた）ときだけ、
            // 辞書の名前に置き換える（「マクドナルト城町店」→「マクドナルド城町店」）。
            let name = best.match.fuzzy
                ? chain.name + (best.match.attached ? "" : " ") + best.branch
                : cleanedMerchant(best.match.text)
            return (name, chain)
        }
        // 2. チェーン名と支店名が別の行（「mister Donut」と「mozoワンダーシティショップ」）。
        if let branch = separateBranch(in: rows, chain: chain, dictionary: dictionary) {
            return ("\(chain.name) \(branch)", chain)
        }
        // 3. チェーン名だけ。
        return (chain.name, chain)
    }

    /// レシートに刷られたチェーンの名前を、上の行から順に探す。
    ///
    /// 見るのは店名になりうる行だけ。値段の付いた行（品）は見ない（「イオン飲料」で
    /// イオンの店と取り違えないため）。下のほうの行は、支店名の付いた行（「コノミヤ 城西店」）と
    /// 会社名の行だけ見る（クーポンの案内の「全国のミスタードーナツで」を拾わないため）。
    static func chainMatches(in rows: [Row], dictionary: ReceiptDictionary) -> [ChainMatch] {
        guard !dictionary.chains.isEmpty else { return [] }
        var matches: [ChainMatch] = []
        for (index, row) in rows.enumerated() {
            let company = isCompanyLine(row.text)
            let near = index < branchSearchRows
            // 読み取りの別の読み方も見る。ロゴの崩れた行で、2番目の読み方が正しいことがある。
            for text in [row.text] + row.alternativeTexts {
                guard let match = chainMatch(
                    in: text,
                    rowIndex: index,
                    dictionary: dictionary,
                    fuzzy: near || company
                ) else { continue }
                // 値段・日付・電話の行は見ない。名前が見つかった行だけ確かめる
                // （正規表現を使う確かめのほうが重いので、全部の行には使わない）。
                guard isChainSearchRow(row.text) else { break }
                if near || company || endsWithShopWord(cleanedBranch(match.suffix, chain: match.chain)) {
                    matches.append(match)
                }
                break
            }
        }
        return matches
    }

    private static func chainMatch(
        in text: String,
        rowIndex: Int,
        dictionary: ReceiptDictionary,
        fuzzy fuzzyAllowed: Bool
    ) -> ChainMatch? {
        let keyed = keyedScalars(text)
        guard keyed.key.count >= 2 else { return nil }

        // 長い別名から当てる（「イオンスタイル」を「イオン」より先に）。
        var best: (chain: ReceiptDictionary.Chain, span: Range<Int>, fuzzy: Bool)?
        for chain in dictionary.chains {
            for alias in chain.keyScalars {
                guard let span = exactSpan(of: alias, in: keyed.key) else { continue }
                // 2文字の名前（「西友」「出光」）は、行の頭にあるときだけ。
                if alias.count <= 2, span.lowerBound != 0 { continue }
                if span.count > (best?.span.count ?? 0) { best = (chain, span, false) }
            }
        }
        if best == nil, fuzzyAllowed {
            search: for chain in dictionary.chains {
                for alias in chain.keyScalars where alias.count >= fuzzyAliasMinimumLength {
                    if let span = fuzzySpan(of: alias, in: keyed.key) {
                        best = (chain, span, true)
                        break search
                    }
                }
            }
        }
        guard let found = best, found.span.upperBound > 0 else { return nil }

        // 名前のあとに続く文字。同じチェーンのほかの別名（「EQVo! エクボスタイル」の後ろ側）も名前に含める。
        var end = found.span.upperBound
        for alias in found.chain.keyScalars {
            let span = exactSpan(of: alias, in: keyed.key)
                ?? (alias.count >= fuzzyAliasMinimumLength ? fuzzySpan(of: alias, in: keyed.key) : nil)
            if let span, span.lowerBound <= end + 1, span.upperBound > end { end = span.upperBound }
        }
        let characters = Array(text)
        let lastOrigin = keyed.origin[end - 1]
        let rest = lastOrigin + 1 < characters.count ? String(characters[(lastOrigin + 1)...]) : ""
        let attached = rest.first.map { !$0.isWhitespace && !$0.isPunctuation } ?? false
        return ChainMatch(
            chain: found.chain,
            rowIndex: rowIndex,
            text: text,
            suffix: rest.trimmingCharacters(in: .whitespacesAndNewlines),
            attached: attached,
            fuzzy: found.fuzzy
        )
    }

    /// 照らし合わせる形の1文字ずつと、それが元の文字の何文字目から来たか。
    /// 見つけた別名の範囲を、元の文字の範囲に戻すために使う。
    static func keyedScalars(_ text: String) -> (key: [Unicode.Scalar], origin: [Int]) {
        var key: [Unicode.Scalar] = []
        var origin: [Int] = []
        for (offset, character) in text.enumerated() {
            forEachKeyScalar(of: character) { scalar in
                key.append(scalar)
                origin.append(offset)
            }
        }
        return (key, origin)
    }

    /// 別名がそのまま入っていれば、その範囲。
    static func exactSpan(of alias: [Unicode.Scalar], in key: [Unicode.Scalar]) -> Range<Int>? {
        guard let first = alias.first, alias.count <= key.count else { return nil }
        for start in 0...(key.count - alias.count) where key[start] == first {
            if key[start..<(start + alias.count)].elementsEqual(alias) {
                return start..<(start + alias.count)
            }
        }
        return nil
    }

    /// 別名が1文字の読み違い（置き換え・抜け・余分）で入っていれば、その範囲。
    private static func fuzzySpan(of alias: [Unicode.Scalar], in key: [Unicode.Scalar]) -> Range<Int>? {
        guard alias.count >= 2 else { return nil }
        for start in key.indices {
            // 1文字違いなら、窓の頭の2文字のどちらかが、別名の頭の2文字のどちらかと合う。
            // 合わない窓は比べない（長いレシートで、ここがいちばん時間を食っていた）。
            let head = key[start]
            let next: Unicode.Scalar? = start + 1 < key.count ? key[start + 1] : nil
            guard head == alias[0] || head == alias[1] || next == alias[0] || next == alias[1] else { continue }
            for length in [alias.count, alias.count - 1, alias.count + 1] where length > 0 {
                let end = start + length
                guard end <= key.count else { continue }
                if withinOneEdit(key[start..<end], alias[...]) { return start..<end }
            }
        }
        return nil
    }

    /// 2つの並びが1文字の違い（置き換え・抜け・余分）までか。
    private static func withinOneEdit(
        _ left: ArraySlice<Unicode.Scalar>,
        _ right: ArraySlice<Unicode.Scalar>
    ) -> Bool {
        if left.count == right.count {
            return zip(left, right).filter { $0 != $1 }.count <= 1
        }
        let (shorter, longer) = left.count < right.count ? (left, right) : (right, left)
        guard longer.count - shorter.count == 1 else { return false }
        var i = shorter.startIndex
        var j = longer.startIndex
        var skipped = false
        while i < shorter.endIndex, j < longer.endIndex {
            if shorter[i] == longer[j] {
                i += 1
                j += 1
            } else {
                if skipped { return false }
                skipped = true
                j += 1
            }
        }
        return true
    }

    /// チェーンの名前を探してよい行。値段の付いた行（品）と、住所・電話・日付の行は見ない。
    private static func isChainSearchRow(_ text: String) -> Bool {
        if endsWithPrice(text) || looksLikeDate(text) || looksLikePhoneNumber(text) { return false }
        return containsLetters(text)
    }

    /// 会社名の行（「イオンリテール株式会社」「EGGS' N THINGS JAPAN株式会社」）。
    static func isCompanyLine(_ text: String) -> Bool {
        ["株式会社", "(株)", "（株）", "有限会社", "合同会社"].contains { text.contains($0) }
    }

    private static func endsWithShopWord(_ text: String) -> Bool {
        let lower = text.lowercased()
        return shopWords.contains { lower.hasSuffix($0) }
    }

    private static func isPlausibleBranch(_ text: String) -> Bool {
        guard text.count >= 2, containsLetters(text), !isCompanyLine(text) else { return false }
        return !looksLikeDate(text) && !looksLikePhoneNumber(text)
    }

    /// チェーン名だけの行の近くにある、支店名だけの行（「mozoワンダーシティショップ」）。
    private static func separateBranch(
        in rows: [Row],
        chain: ReceiptDictionary.Chain,
        dictionary: ReceiptDictionary
    ) -> String? {
        for row in rows.prefix(branchSearchRows) {
            guard isMerchantCandidate(row) else { continue }
            let branch = cleanedBranch(row.text, chain: chain)
            guard isPlausibleBranch(branch), endsWithShopWord(branch) else { continue }
            // ほかのチェーンの名前が入っている行は、そのチェーンの店名。
            let key = dictionaryKey(branch)
            if dictionary.chains.contains(where: { other in
                other != chain && other.keys.contains { $0.count >= 3 && key.contains($0) }
            }) { continue }
            return branch
        }
        return nil
    }

    /// 支店名の候補を整える。
    ///
    /// - チェーン名の一部の英単語（「2 Things名古屋PARC0店」の Things）を落とす
    /// - 頭に付いた数字・記号・1文字の英字（読み違いのかけら）を落とす
    /// - 英大文字に続く「0」を「O」に直す（「PARC0」→「PARCO」。数字の0と英字のOの読み違い）
    static func cleanedBranch(_ text: String, chain: ReceiptDictionary.Chain) -> String {
        var value = text
        if let words = regex("[A-Za-z']+") {
            let found = words.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed()
            for match in found {
                guard let range = Range(match.range, in: value) else { continue }
                let key = dictionaryKey(String(value[range]))
                if key.count >= 3, chain.keys.contains(where: { $0.contains(key) }) {
                    value.removeSubrange(range)
                }
            }
        }
        // 頭のかけら（数字、記号、空白、1文字だけの英字）を落とす。
        while let first = value.first {
            if first.isWhitespace || first.isNumber || first.isPunctuation || first.isSymbol {
                value.removeFirst()
                continue
            }
            if first.isASCII, first.isLetter {
                let rest = value.dropFirst()
                if rest.first.map({ $0.isWhitespace }) ?? true {
                    value.removeFirst()
                    continue
                }
            }
            break
        }
        if let zero = regex("(?<=[A-Z])0(?![0-9])") {
            value = zero.stringByReplacingMatches(
                in: value,
                range: NSRange(value.startIndex..., in: value),
                withTemplate: "O"
            )
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: " 　*※-–—・|:：「」"))
    }
}
