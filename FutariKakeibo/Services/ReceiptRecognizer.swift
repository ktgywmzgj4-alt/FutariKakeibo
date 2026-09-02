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
        guard let cgImage = image.cgImage else {
            throw RecognitionError.invalidImage
        }
        // 写真は撮った向きの情報を別に持っている。cgImageだけを渡すと
        // 横倒しのまま読み取ってしまうため、向きも一緒に伝える。
        let orientation = cgOrientation(image.imageOrientation)

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
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return nil }
                        let box = observation.boundingBox
                        return RecognizedLine(
                            text: text,
                            minX: Double(box.minX),
                            maxX: Double(box.maxX),
                            // Visionの原点は左下。上を0にして読み順に合わせる。
                            midY: Double(1 - box.midY),
                            height: Double(box.height)
                        )
                    }
                    continuation.resume(returning: lines)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func cgOrientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: .up
        case .upMirrored: .upMirrored
        case .down: .down
        case .downMirrored: .downMirrored
        case .left: .left
        case .leftMirrored: .leftMirrored
        case .right: .right
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
