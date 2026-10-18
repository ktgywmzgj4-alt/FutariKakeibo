import XCTest
@testable import FutariKakeibo

/// 実物のレシートで、読み取りがどれだけ当たるかを数える。
///
/// 結果は CI の記録に `[OCR評価]` で始まる行として出る。読み取りを直すたびにこれを見比べ、
/// **下がった変更は入れない。** 下限（`floors`）を下回るとテストが落ちる。
///
/// 数えるのは `ReceiptCorpus` の実物のレシートだけ。作った例は混ぜない。
/// 時間はCIのシミュレータで測るので、実機の値とは違う（比べるのは前後の差）。
///
/// 名前の先頭を Z にしてあるのは、テストが名前順に走るため。CIの記録の**最後のほう**に
/// 数字が出るので、記録の末尾を読むだけで見つかる。
final class ZReceiptScoreboardTests: XCTestCase {
    /// これより下がったら落とす。値は測った結果そのもの。改善が入ったら、その値に上げる。
    ///
    /// - 基準値（改善の前、4fd0422）: 店名 7・11、合計 12、日付 13、種類 12、明細 47・45
    /// - 第1段階（6c98f0f）: 合計 13、明細 64・64
    /// - 第2段階（b3b192b、run 39127806426）: 店名 12・12、明細 67・67
    private let floors = (
        merchantExact: 12, merchantChain: 12, total: 13, date: 13, category: 12,
        itemsNamed: 67, itemsPriced: 67
    )

    func testScoreboard() {
        let board = ReceiptParser.$logsDecisions.withValue(false) {
            ReceiptScoreboard(samples: ReceiptCorpus.all)
        }
        for line in board.report() {
            print("[OCR評価] \(line)")
        }
        XCTAssertEqual(board.results.count, ReceiptCorpus.all.count)

        let results = board.results
        let scored = results.compactMap(\.items)
        XCTAssertGreaterThanOrEqual(results.filter(\.merchantExact).count, floors.merchantExact, "店名（支店名まで）")
        XCTAssertGreaterThanOrEqual(results.filter(\.merchantChain).count, floors.merchantChain, "店名（チェーン名まで）")
        XCTAssertGreaterThanOrEqual(results.filter(\.totalCorrect).count, floors.total, "合計金額")
        XCTAssertGreaterThanOrEqual(results.filter(\.dateCorrect).count, floors.date, "日付")
        XCTAssertGreaterThanOrEqual(results.filter(\.categoryCorrect).count, floors.category, "種類")
        XCTAssertGreaterThanOrEqual(scored.reduce(0) { $0 + $1.named }, floors.itemsNamed, "明細の抽出")
        XCTAssertGreaterThanOrEqual(scored.reduce(0) { $0 + $1.priced }, floors.itemsPriced, "明細の値段")
    }

    /// 1回保存したあとに、同じ店のレシートを読んだときの当たり方（第3段階: 直したことから覚える）。
    ///
    /// 保存は正解の店名・種類・合計で行い、読み取りと違えば「人が直した」とする。
    /// 実物のレシートには同じ店の2枚目がほとんど無い（EQVo! と イオンの2組だけ）ので、
    /// - 同じ1枚をもう一度読む（覚えたことが効くかどうかの上限。2枚目の実物ではない）
    /// - 同じ店の2枚目（EQVo! 8月→9月、イオン 9月→10月）
    /// を分けて数える。**覚えたことで、覚える前より悪くなった1枚があれば落とす。**
    func testLearningFromOneSave() {
        ReceiptParser.$logsDecisions.withValue(false) {
            let samples = ReceiptCorpus.all
            let before = samples.map { ReceiptScoreboard.read($0, memos: []) }
            let again = samples.map { sample in
                ReceiptScoreboard.read(sample, memos: ReceiptScoreboard.remembered(after: sample, memos: []))
            }
            let pairs = [
                (ReceiptCorpus.eqvoAugust, ReceiptCorpus.eqvoSeptember),
                (ReceiptCorpus.aeonSeptember, ReceiptCorpus.aeonOctober)
            ]
            let second = pairs.map { first, next in
                ReceiptScoreboard.read(next, memos: ReceiptScoreboard.remembered(after: first, memos: []))
            }
            let secondBefore = pairs.map { ReceiptScoreboard.read($0.1, memos: []) }

            print("[OCR評価] 1回保存したあと（同じ1枚をもう一度。上限の目安） "
                + ReceiptScoreboard.hits(again, samples: samples))
            print("[OCR評価] 覚える前（同じ13枚） " + ReceiptScoreboard.hits(before, samples: samples))
            print("[OCR評価] 同じ店の2枚目（EQVo! 8月→9月・イオン 9月→10月） "
                + ReceiptScoreboard.hits(second, samples: pairs.map { $0.1 })
                + "（覚える前 " + ReceiptScoreboard.hits(secondBefore, samples: pairs.map { $0.1 }) + "）")

            for (index, sample) in samples.enumerated() {
                let old = ReceiptScoreboard.correctness(before[index], sample: sample)
                let new = ReceiptScoreboard.correctness(again[index], sample: sample)
                XCTAssertTrue(!old.merchant || new.merchant, "\(sample.name): 覚えたあとに店名が外れた")
                XCTAssertTrue(!old.category || new.category, "\(sample.name): 覚えたあとに種類が外れた")
                XCTAssertTrue(!old.total || new.total, "\(sample.name): 覚えたあとに合計が外れた")
            }
            for (index, pair) in pairs.enumerated() {
                let old = ReceiptScoreboard.correctness(secondBefore[index], sample: pair.1)
                let new = ReceiptScoreboard.correctness(second[index], sample: pair.1)
                XCTAssertTrue(!old.merchant || new.merchant, "\(pair.1.name): 2枚目の店名が外れた")
                XCTAssertTrue(!old.category || new.category, "\(pair.1.name): 2枚目の種類が外れた")
                XCTAssertTrue(!old.total || new.total, "\(pair.1.name): 2枚目の合計が外れた")
            }
        }
    }

    /// 全部を1回ずつ読む時間と、そのあいだに増えたメモリ。
    func testParsingCost() {
        let samples = ReceiptCorpus.all
        let calendar = ReceiptCorpus.calendar
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            ReceiptParser.$logsDecisions.withValue(false) {
                for sample in samples {
                    _ = ReceiptParser.parse(lines: sample.lines, now: sample.now, calendar: calendar)
                }
            }
        }
    }

    /// 比べ方そのものの確かめ。ここが狂うと、正解率の数字が全部あてにならない。
    func testNameMatchingToleratesSmallMisreadsButNotDifferentItems() {
        XCTAssertGreaterThanOrEqual(ReceiptScoreboard.nameSimilarity("ほうれん草", "まうれん車"), 0.5)
        XCTAssertGreaterThanOrEqual(ReceiptScoreboard.nameSimilarity("抹茶ラテ", "単)C 抹茶ラテ オリジナル"), 0.5)
        XCTAssertGreaterThanOrEqual(ReceiptScoreboard.nameSimilarity("ＴＶえのき茸", "TVえのき茸"), 0.99)
        XCTAssertLessThan(ReceiptScoreboard.nameSimilarity("ロコモコ", "アイスコーヒー"), 0.5)
        XCTAssertLessThan(ReceiptScoreboard.nameSimilarity("きゅうり", "土れんこん"), 0.5)
    }
}

/// 正解と読み取り結果を比べて数える。
struct ReceiptScoreboard {
    struct ItemScore {
        var expected: Int
        var extracted: Int
        /// 品名が正解のどれかと合ったもの。
        var named: Int
        /// そのうち値段まで合ったもの。
        var priced: Int
        /// 拾えなかった正解の品。
        var missed: [String]
        /// 品名は合ったが値段が違った品。「品名(読んだ値段→正解)」の形。
        var wrongPrice: [String]
        /// 正解に無いのに拾った品。
        var extra: [String]
    }

    struct Outcome {
        var sample: ReceiptCorpus.Sample
        var draft: ReceiptDraft
        var merchantExact: Bool
        var merchantChain: Bool
        var totalCorrect: Bool
        var dateCorrect: Bool
        var categoryCorrect: Bool
        /// 明細を数えるレシートだけ値が入る。
        var items: ItemScore?
        var milliseconds: Double
    }

    /// 品名がこれ以上似ていれば同じ品とみなす。
    static let matchThreshold = 0.5

    let results: [Outcome]

    init(samples: [ReceiptCorpus.Sample], repetitions: Int = 20) {
        let calendar = ReceiptCorpus.calendar
        let clock = ContinuousClock()
        results = samples.map { sample in
            var draft = ReceiptParser.parse(lines: sample.lines, now: sample.now, calendar: calendar)
            let elapsed = clock.measure {
                for _ in 0..<repetitions {
                    draft = ReceiptParser.parse(lines: sample.lines, now: sample.now, calendar: calendar)
                }
            }
            let expected = sample.expected
            let merchant = Self.folded(draft.merchant)
            let exact = !merchant.isEmpty && expected.merchants.contains { Self.folded($0) == merchant }
            let chain = exact || (!merchant.isEmpty && expected.chains.contains { chain in
                let key = Self.folded(chain)
                return !key.isEmpty && merchant.contains(key)
            })
            return Outcome(
                sample: sample,
                draft: draft,
                merchantExact: exact,
                merchantChain: chain,
                totalCorrect: draft.amount == expected.total,
                dateCorrect: draft.date.map { calendar.isDate($0, inSameDayAs: expected.date) } ?? false,
                categoryCorrect: draft.suggestedCategory == expected.category,
                items: expected.items.map { Self.scoreItems(expected: $0, extracted: draft.items) },
                milliseconds: Self.milliseconds(elapsed) / Double(max(repetitions, 1))
            )
        }
    }

    // MARK: - 記録に出す形

    func report() -> [String] {
        let count = results.count
        let fromDevice = results.filter { $0.sample.source == .deviceText }.count
        var lines = [
            "実物のレシート \(count)枚（\(ReceiptCorpus.Source.deviceText.rawValue) \(fromDevice)枚・"
                + "\(ReceiptCorpus.Source.reconstructed.rawValue) \(count - fromDevice)枚）",
            Self.ratio("店名（支店名まで）", results.filter(\.merchantExact).count, count),
            Self.ratio("店名（チェーン名まで）", results.filter(\.merchantChain).count, count),
            Self.ratio("合計金額", results.filter(\.totalCorrect).count, count),
            Self.ratio("日付", results.filter(\.dateCorrect).count, count),
            Self.ratio("種類", results.filter(\.categoryCorrect).count, count)
        ]

        let scored = results.compactMap(\.items)
        let expected = scored.reduce(0) { $0 + $1.expected }
        let named = scored.reduce(0) { $0 + $1.named }
        let priced = scored.reduce(0) { $0 + $1.priced }
        let extra = scored.reduce(0) { $0 + $1.extra.count }
        lines.append(Self.ratio("明細の抽出率（品名が合った品／正解の品）", named, expected)
            + "（明細をそろえた \(scored.count)枚）")
        lines.append(Self.ratio("品名と値段の対応（値段まで合った品／品名が合った品）", priced, named))
        lines.append(Self.ratio("明細の値段まで合った品／正解の品", priced, expected))
        lines.append("正解に無い品を拾った数 \(extra)")

        let times = results.map(\.milliseconds)
        let mean = times.isEmpty ? 0 : times.reduce(0, +) / Double(times.count)
        let slowest = times.max() ?? 0
        lines.append(String(format: "解析時間 1枚あたり 平均 %.2fms・最大 %.2fms（CIのシミュレータ）", mean, slowest))

        lines.append(contentsOf: results.map(Self.detail))
        return lines
    }

    private static func ratio(_ label: String, _ hit: Int, _ total: Int) -> String {
        guard total > 0 else { return "\(label) 0/0" }
        let percent = String(format: "%.1f", Double(hit) * 100 / Double(total))
        return "\(label) \(hit)/\(total) = \(percent)%"
    }

    private static func detail(_ result: Outcome) -> String {
        func mark(_ ok: Bool) -> String { ok ? "○" : "×" }
        let draft = result.draft
        let merchantMark = result.merchantExact ? "○" : (result.merchantChain ? "△" : "×")
        var parts = [
            "・\(result.sample.name):",
            "店名\(merchantMark)「\(draft.merchant)」",
            "合計\(mark(result.totalCorrect)) \(draft.amount.map(String.init) ?? "なし")"
                + (draft.amountNeedsConfirmation ? "（確認を求める）" : ""),
            "日付\(mark(result.dateCorrect))",
            "種類\(mark(result.categoryCorrect)) \(draft.suggestedCategory.rawValue)",
            // どの1枚が遅いかを見るため。
            String(format: "%.1fms", result.milliseconds)
        ]
        if !result.totalCorrect {
            // 外したときは、何点で何に負けたかを出す。CIの記録だけで原因を追えるように。
            let items = draft.items
            let candidates = ReceiptParser.totalCandidates(
                in: ReceiptParser.rows(from: result.sample.lines),
                itemsTotal: items.isEmpty ? nil : items.reduce(0) { $0 + $1.netAmount },
                itemsCount: items.count,
                itemsCapped: items.count >= ReceiptParser.maximumItems,
                summary: ReceiptParser.summary(of: ReceiptParser.rows(from: result.sample.lines))
            )
            let top = candidates.sorted { ($0.score, $0.amount) > ($1.score, $1.amount) }.prefix(3)
            parts.append("合計の候補: " + top.map { "\($0.amount)(\($0.score)点 \($0.reason))" }.joined(separator: "、"))
        }
        if let items = result.items {
            parts.append("明細 \(items.named)/\(items.expected)（値段も合う \(items.priced)・余分 \(items.extra.count)）")
            if !items.missed.isEmpty {
                parts.append("拾えなかった品: " + items.missed.joined(separator: "、"))
            }
            if !items.wrongPrice.isEmpty {
                parts.append("値段違い: " + items.wrongPrice.joined(separator: "、"))
            }
            if !items.extra.isEmpty {
                parts.append("余分: " + items.extra.joined(separator: "、"))
            }
        } else {
            parts.append("明細は数えない（拾った \(draft.items.count)件）")
        }
        return parts.joined(separator: " ")
    }

    // MARK: - 覚えたことを使う

    /// 覚えた店を使って読む。画面と同じ順番（書き方を使って読み直し → 覚えた店名と種類）。
    static func read(_ sample: ReceiptCorpus.Sample, memos: [MerchantMemo]) -> ReceiptDraft {
        let draft = ReceiptInterpreter.ruleDraft(
            lines: sample.lines,
            now: sample.now,
            calendar: ReceiptCorpus.calendar,
            memos: memos
        )
        return MerchantMemory.applying(memos, to: draft)
    }

    /// 1枚を読んで、正解の店名・種類・合計で保存したことにする。読み取りと違えば「人が直した」。
    static func remembered(after sample: ReceiptCorpus.Sample, memos: [MerchantMemo]) -> [MerchantMemo] {
        let shown = read(sample, memos: memos)
        guard let key = shown.shopKey else { return memos }
        let expected = sample.expected
        let merchantRight = expected.merchants.contains { folded($0) == folded(shown.merchant) }
        let merchant = merchantRight ? shown.merchant : (expected.merchants.first ?? shown.merchant)
        return MerchantMemory.remembering(
            memos,
            MerchantObservation(
                key: key,
                identifiers: shown.shopIdentifiers,
                merchant: merchant,
                category: expected.category,
                corrected: !merchantRight || shown.suggestedCategory != expected.category,
                businessKey: shown.businessKey,
                totalLabel: ReceiptParser.totalLabel(forTotal: expected.total, inReceiptText: shown.recognizedText),
                totalCorrected: shown.amount != expected.total
            ),
            now: sample.now
        )
    }

    static func correctness(
        _ draft: ReceiptDraft,
        sample: ReceiptCorpus.Sample
    ) -> (merchant: Bool, category: Bool, total: Bool) {
        let merchant = folded(draft.merchant)
        return (
            !merchant.isEmpty && sample.expected.merchants.contains { folded($0) == merchant },
            draft.suggestedCategory == sample.expected.category,
            draft.amount == sample.expected.total
        )
    }

    static func hits(_ drafts: [ReceiptDraft], samples: [ReceiptCorpus.Sample]) -> String {
        let marks = zip(drafts, samples).map { correctness($0, sample: $1) }
        let count = samples.count
        let merchants = marks.filter { $0.merchant }.count
        let categories = marks.filter { $0.category }.count
        let totals = marks.filter { $0.total }.count
        return "店名 \(merchants)/\(count)・種類 \(categories)/\(count)・合計 \(totals)/\(count)"
    }

    // MARK: - 比べ方

    static func scoreItems(expected: [(name: String, amount: Int)], extracted: [ReceiptItem]) -> ItemScore {
        var remaining = Array(extracted.indices)
        var named = 0
        var priced = 0
        var missed: [String] = []
        var wrongPrice: [String] = []

        for item in expected {
            var best: (index: Int, similarity: Double)?
            for index in remaining {
                let candidate = extracted[index]
                var similarity = nameSimilarity(item.name, candidate.name)
                // 同じくらい似ているなら、値段の合うほうを選ぶ。
                if candidate.amount == item.amount { similarity += 0.01 }
                if similarity > (best?.similarity ?? 0) {
                    best = (index, similarity)
                }
            }
            guard let best, best.similarity >= matchThreshold else {
                missed.append(item.name)
                continue
            }
            remaining.removeAll { $0 == best.index }
            named += 1
            let amount = extracted[best.index].amount
            if amount == item.amount {
                priced += 1
            } else {
                wrongPrice.append("\(item.name)(\(amount)→\(item.amount))")
            }
        }

        return ItemScore(
            expected: expected.count,
            extracted: extracted.count,
            named: named,
            priced: priced,
            missed: missed,
            wrongPrice: wrongPrice,
            extra: remaining.map { extracted[$0].name }
        )
    }

    /// 品名の似ている度合い。1が同じ、0がまったく違う。
    ///
    /// 全角と半角、空白と記号の違いは見ない。片方がもう片方をそっくり含むなら同じ品とみなす
    /// （「抹茶ラテ」と「C 抹茶ラテ オリジナル」）。それ以外は1文字ずつの違いの数で測る。
    static func nameSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let left = Array(folded(lhs))
        let right = Array(folded(rhs))
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let (shorter, longer) = left.count <= right.count ? (left, right) : (right, left)
        if shorter.count >= 3, String(longer).contains(String(shorter)) { return 1 }
        return 1 - Double(editDistance(left, right)) / Double(longer.count)
    }

    /// 比べるための形。互換文字をそろえ（全角英数を半角に、半角カナを全角に）、
    /// 小文字にして、文字と数字以外を落とす。
    static func folded(_ text: String) -> String {
        let normalized = text.precomposedStringWithCompatibilityMapping.lowercased()
        var scalars = String.UnicodeScalarView()
        for scalar in normalized.unicodeScalars where CharacterSet.alphanumerics.contains(scalar) {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    private static func editDistance(_ left: [Character], _ right: [Character]) -> Int {
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }
        var previous = Array(0...right.count)
        var current = [Int](repeating: 0, count: right.count + 1)
        for i in 1...left.count {
            current[0] = i
            for j in 1...right.count {
                let cost = left[i - 1] == right[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[right.count]
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1_000_000_000_000_000
    }
}
