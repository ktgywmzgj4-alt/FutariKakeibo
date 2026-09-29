import UIKit
import Vision

enum ReceiptRecognizer {
    enum RecognitionError: LocalizedError {
        case invalidImage
        case noText

        var errorDescription: String? {
            switch self {
            case .invalidImage: "撮影した画像を読み込めませんでした。"
            case .noText: "文字を読み取れませんでした。手入力で保存できます。"
            }
        }
    }

    static func recognize(images: [UIImage]) async throws -> [RecognizedLine] {
        try await capture(images: images).lines
    }

    /// 診断は呼び出し元の画面だけが保持する。自動保存や自動送信はしない。
    static func capture(images: [UIImage]) async throws -> ReceiptOCRReport {
        var report = ReceiptOCRReport()
        for image in images {
            report.pages.append(try await recognize(image: image))
        }
        guard !report.lines.isEmpty else {
            throw RecognitionError.noText
        }
        return report
    }

    private static func recognize(image: UIImage) async throws -> ReceiptOCRReport.Page {
        // 斜めから撮った1枚は、先に正面から撮った形へ直す。
        // 四隅が見つからなければ、向きだけそろえた元の画像がそのまま返る。
        let prepared = await ReceiptImageRectifier.rectified(image)
        guard let cgImage = prepared.cgImage else {
            throw RecognitionError.invalidImage
        }
        // 写真は撮った向きの情報を別に持っている。cgImageだけを渡すと
        // 横倒しのまま読み取ってしまうため、向きも一緒に伝える。
        // 補正できた1枚は立った状態（`.up`）で返るので、ここは素通りになる。
        let orientation = ReceiptImageRectifier.cgOrientation(prepared.imageOrientation)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.revision = VNRecognizeTextRequestRevision3
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["ja-JP", "en-US"]
                request.usesLanguageCorrection = true
                // レシートは但し書きや明細の文字が小さい。既定より低くして拾う。
                request.minimumTextHeight = 0.008

                do {
                    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
                    try handler.perform([request])
                    let observations = request.results ?? []
                    let fragments = observations.map { observation -> ReceiptOCRReport.Fragment in
                        let candidate = observation.topCandidates(1).first
                        let text = candidate?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let box = observation.boundingBox
                        let line = text.isEmpty ? nil : ReceiptOCRReport.Line(
                            text: text,
                            minX: Double(box.minX),
                            maxX: Double(box.maxX),
                            // Visionの原点は左下。上を0にして読み順に合わせる。
                            midY: Double(1 - box.midY),
                            height: Double(box.height),
                            slope: baselineSlope(of: observation)
                        )
                        return ReceiptOCRReport.Fragment(
                            text: candidate?.string,
                            confidence: candidate?.confidence,
                            boundingBox: .init(x: Double(box.origin.x), y: Double(box.origin.y),
                                               width: Double(box.width), height: Double(box.height)),
                            parserLine: line
                        )
                    }
                    continuation.resume(returning: ReceiptOCRReport.Page(
                        pixelWidth: cgImage.width, pixelHeight: cgImage.height,
                        orientation: orientation.rawValue, fragments: fragments
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 読み取った文字の下辺の傾き。
    ///
    /// Visionは文字の四隅を返すので、行がどれだけ傾いているかを直接測れる。
    /// 台形補正で直しきれなかったぶんが、ここに残る。
    /// Visionの原点は左下、`RecognizedLine` は左上なので、符号を逆にして持つ。
    private static func baselineSlope(of observation: VNRecognizedTextObservation) -> Double {
        let run = Double(observation.bottomRight.x - observation.bottomLeft.x)
        // 短すぎる断片は両端が近く、傾きが跳ね上がる。測れなかったことにする。
        guard run > 0.001 else { return 0 }
        let rise = Double(observation.bottomRight.y - observation.bottomLeft.y)
        return -rise / run
    }
}

/// JSONをデコードすると、丸めずに保存したパーサ入力をそのままテストで再生できる。
/// boundingBoxは補正後の画像に対するVision座標（左下原点、0〜1）。
/// parserLineは変換済みの実入力（左上原点）。pages/ fragmentsは受信順を保つ。
struct ReceiptOCRReport: Codable, Sendable {
    struct Box: Codable, Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    struct Line: Codable, Sendable {
        var text: String
        var minX: Double
        var maxX: Double
        var midY: Double
        var height: Double
        var slope: Double

        var recognizedLine: RecognizedLine {
            RecognizedLine(text: text, minX: minX, maxX: maxX, midY: midY, height: height, slope: slope)
        }
    }

    struct Fragment: Codable, Sendable {
        var text: String?
        var confidence: Float?
        var boundingBox: Box
        var parserLine: Line?
    }

    struct Page: Codable, Sendable {
        var pixelWidth: Int
        var pixelHeight: Int
        var orientation: UInt32
        var fragments: [Fragment]
    }

    struct Result: Codable, Sendable {
        var amount: Int?
        var date: Date?
        var itemAmounts: [Int]

        init(_ draft: ReceiptDraft) {
            amount = draft.amount
            date = draft.date
            itemAmounts = draft.items.map(\.amount)
        }
    }

    struct Candidate: Codable, Sendable {
        var amount: Int
        var rowIndex: Int
        var score: Int
        var reason: String
    }

    struct Analysis: Codable, Sendable {
        var now: Date
        var calendarIdentifier: String
        var timeZoneIdentifier: String
        var rows: [String]
        var candidates: [Candidate]
        var parser: Result
        var aiReturnedAnswer: Bool
        var aiAmount: Int?
        var aiDate: String?
        var interpreted: Result
        var displayedAmount: String?
        var displayedDate: Date?
    }

    var schemaVersion = 1
    var capturedAt = Date.now
    var build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    var operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
    var visionRevision = VNRecognizeTextRequestRevision3
    var recognitionLanguages = ["ja-JP", "en-US"]
    var recognitionLevel = "accurate"
    var usesLanguageCorrection = true
    var minimumTextHeight = 0.008
    var coordinateSystem = "boundingBox: normalized Vision bottom-left after rectification; parserLine: top-left"
    var pages: [Page] = []
    var analysis: Analysis?

    var lines: [RecognizedLine] {
        pages.flatMap { $0.fragments.compactMap { $0.parserLine?.recognizedLine } }
    }

    mutating func recordAnalysis(base: ReceiptDraft, answer: ReceiptAnswer?, final: ReceiptDraft,
                                 now: Date, calendar: Calendar) {
        let rows = ReceiptParser.rows(from: lines)
        let itemsTotal = base.items.isEmpty ? nil : base.items.reduce(0) { $0 + $1.amount }
        analysis = Analysis(
            now: now, calendarIdentifier: String(describing: calendar.identifier),
            timeZoneIdentifier: calendar.timeZone.identifier, rows: rows.map(\.text),
            candidates: ReceiptParser.totalCandidates(in: rows, itemsTotal: itemsTotal).map {
                Candidate(amount: $0.amount, rowIndex: $0.rowIndex, score: $0.score, reason: $0.reason)
            },
            parser: Result(base), aiReturnedAnswer: answer != nil,
            aiAmount: answer?.total, aiDate: answer?.date, interpreted: Result(final)
        )
    }

    func exportText() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Dateの既定の数値形式も含め、JSONDecoder()でそのまま再生できる。
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}
