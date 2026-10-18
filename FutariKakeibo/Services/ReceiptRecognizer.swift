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
        var lines: [RecognizedLine] = []
        for image in images {
            lines.append(contentsOf: try await recognize(image: image))
        }
        guard !lines.isEmpty else {
            throw RecognitionError.noText
        }
        return lines
    }

    private static func recognize(image: UIImage) async throws -> [RecognizedLine] {
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
                    let lines = observations.compactMap { observation -> RecognizedLine? in
                        // 読み方の候補を3つまで受け取る。1つめがいちばん確からしいもの。
                        // 読み取りは1回だけで、候補を増やしても時間はほとんど変わらない。
                        let candidates = observation.topCandidates(3)
                        guard let best = candidates.first else { return nil }
                        let text = best.string.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return nil }
                        let alternatives = candidates.dropFirst()
                            .map { $0.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty && $0 != text }
                        let box = observation.boundingBox
                        return RecognizedLine(
                            text: text,
                            minX: Double(box.minX),
                            maxX: Double(box.maxX),
                            // Visionの原点は左下。上を0にして読み順に合わせる。
                            midY: Double(1 - box.midY),
                            height: Double(box.height),
                            slope: baselineSlope(of: observation),
                            alternatives: alternatives,
                            confidence: Double(best.confidence)
                        )
                    }
                    continuation.resume(returning: lines)
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
