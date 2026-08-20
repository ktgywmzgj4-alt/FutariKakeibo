import UIKit
@preconcurrency import Vision

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

    static func recognize(images: [UIImage]) async throws -> String {
        var pages: [String] = []
        for image in images {
            pages.append(try await recognize(image: image))
        }
        let combined = pages.joined(separator: "\n")
        guard !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecognitionError.noText
        }
        return combined
    }

    private static func recognize(image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw RecognitionError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cgImage).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
