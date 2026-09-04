import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

/// 斜めから撮ったレシートを、正面から撮った形に直してから読み取りへ渡す。
///
///     撮った画像 → 向きをそろえる → 四隅を探す → 台形をのばす → 読み取りへ
///
/// **どの段階でも、少しでも怪しければ何もせず元の画像を使わせる。**
/// 直そうとして文字を切り落とすより、直さずに読むほうがましだから。
enum ReceiptImageRectifier {
    /// 四隅の検出をどれだけ信用するか。
    private static let minimumConfidence: Float = 0.5
    /// レシートが画像に占める面積の下限。これより小さい四角は背景の模様。
    private static let minimumAreaRatio = 0.15
    /// 直したあとの縦横比の上限。レシートは細長いが、これを超えるのは検出の失敗。
    private static let maximumAspectRatio = 12.0

    /// 読み取りに渡す1枚を用意する。直せたときだけ、直した画像が返る。
    ///
    /// 画像の処理は重いので、呼んだところを止めないよう別のところで動かす。
    /// 並行の境界をまたぐのは `CGImage` と向きだけにして、`UIImage` は持ち込まない。
    static func rectified(_ image: UIImage) async -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        // 写真は「撮った向き」を画素とは別に持っている。Vision にも Core Image にも
        // その向きを伝えれば、どちらも同じ「立てた状態」の座標で話が通じる。
        // 画像を描き直して立て直す必要はない（1回ぶん処理が減る）。
        let orientation = cgOrientation(image.imageOrientation)

        let corrected: CGImage? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: flattened(cgImage, orientation: orientation))
            }
        }

        // 直せなかったら元の1枚をそのまま返す。向きの情報も付いたままなので、
        // 読み取り側はこれまでどおりに扱える。
        guard let corrected else { return image }
        return UIImage(cgImage: corrected, scale: 1, orientation: .up)
    }

    private static func flattened(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> CGImage? {
        guard let corners = documentCorners(in: image, orientation: orientation) else {
            return nil
        }
        return perspectiveCorrected(image, orientation: orientation, corners: corners)
    }

    static func cgOrientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
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

    // MARK: - 四隅を探す

    private static func documentCorners(
        in image: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> VNRectangleObservation? {
        // まず「書類」として探す。レシートは机や布の上に置かれることが多く、
        // 四角を総当たりで探すより、書類そのものを見つけるほうがよく当たる。
        let segmentation = VNDetectDocumentSegmentationRequest()
        let segmented = observations(
            from: segmentation,
            cgImage: image,
            orientation: orientation
        )
        if let found = segmented.first(where: { isUsable($0) }) {
            return found
        }

        // 見つからなければ、細長い四角として探す。
        let rectangles = VNDetectRectanglesRequest()
        // レシートは縦に細長い。既定の 0.5 では弾かれてしまう。
        rectangles.minimumAspectRatio = 0.1
        rectangles.maximumAspectRatio = 1.0
        rectangles.minimumSize = 0.2
        rectangles.minimumConfidence = minimumConfidence
        // 斜めから撮ると四隅は直角ではなくなる。そのぶんを許す。
        rectangles.quadratureTolerance = 35
        rectangles.maximumObservations = 1
        let found = observations(
            from: rectangles,
            cgImage: image,
            orientation: orientation
        )
        return found.first(where: { isUsable($0) })
    }

    /// 1回の探索ごとに新しい handler を作る。使い回さない。
    private static func observations(
        from request: VNImageBasedRequest,
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> [VNRectangleObservation] {
        do {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try handler.perform([request])
            return request.results as? [VNRectangleObservation] ?? []
        } catch {
            // 見つけられなかっただけ。元の画像で読み取りを続ける。
            return []
        }
    }

    // MARK: - 採用してよい四隅か

    static func isUsable(_ observation: VNRectangleObservation) -> Bool {
        isUsableQuad(
            corners: [
                observation.topLeft,
                observation.topRight,
                observation.bottomRight,
                observation.bottomLeft
            ],
            confidence: observation.confidence
        )
    }

    /// 検出した四隅を採用してよいか。
    ///
    /// 検出は外すことがある。テーブルの縁やレシートの一部だけを拾うと、
    /// **文字が切り落とされて読めなくなる**。少しでも疑わしいものは落とす。
    /// 引数は左上から時計回りの4点。画像の左下が (0,0)、右上が (1,1)。
    static func isUsableQuad(corners: [CGPoint], confidence: Float) -> Bool {
        guard corners.count == 4, confidence >= minimumConfidence else { return false }
        // 画像の外を指す点は検出の失敗。
        let inside = corners.allSatisfy { point in
            point.x >= 0 && point.x <= 1 && point.y >= 0 && point.y <= 1
        }
        guard inside, isConvex(corners), area(of: corners) >= minimumAreaRatio else {
            return false
        }

        let width = max(distance(corners[0], corners[1]), distance(corners[3], corners[2]))
        let height = max(distance(corners[0], corners[3]), distance(corners[1], corners[2]))
        guard width > 0, height > 0 else { return false }
        return max(width, height) / min(width, height) <= maximumAspectRatio
    }

    /// 四角がへこんでいないか。ねじれた四隅をのばすと絵が裏返る。
    private static func isConvex(_ corners: [CGPoint]) -> Bool {
        var sawPositive = false
        var sawNegative = false
        for index in corners.indices {
            let a = corners[index]
            let b = corners[(index + 1) % corners.count]
            let c = corners[(index + 2) % corners.count]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if cross > 0 { sawPositive = true }
            if cross < 0 { sawNegative = true }
            if sawPositive && sawNegative { return false }
        }
        return sawPositive || sawNegative
    }

    /// 四角の面積。座標は画像の幅と高さで割ってあるので、そのまま面積の割合になる。
    private static func area(of corners: [CGPoint]) -> Double {
        var total = 0.0
        for index in corners.indices {
            let a = corners[index]
            let b = corners[(index + 1) % corners.count]
            total += Double(a.x * b.y - b.x * a.y)
        }
        return abs(total) / 2
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        Double(hypot(b.x - a.x, b.y - a.y))
    }

    /// そのまま計算に使える大きさか。
    ///
    /// Core Imageの画像は「無限に広い」ことがあり、`extent` に無限大や NaN が入る。
    /// それを画素の位置に掛けると、以降の計算がまるごと壊れる。
    ///
    /// `CGRect` に `isFinite` は無い。SwiftUI が同じ名前のものを内部用に持っているが、
    /// アプリからは使えない（`package` のため）。四隅を自分で確かめる。
    private static func isUsable(extent: CGRect) -> Bool {
        guard !extent.isNull, !extent.isInfinite else { return false }
        return extent.origin.x.isFinite
            && extent.origin.y.isFinite
            && extent.size.width.isFinite
            && extent.size.height.isFinite
    }

    // MARK: - 台形をのばす

    private static func perspectiveCorrected(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation,
        corners: VNRectangleObservation
    ) -> CGImage? {
        // Core Image 側も同じ向きに立てる。これで Vision の返した座標がそのまま使える。
        let source = CIImage(cgImage: image).oriented(orientation)
        let extent = source.extent
        guard isUsable(extent: extent), extent.width > 0, extent.height > 0 else { return nil }

        // Vision も Core Image も原点は左下。割合を画素の位置に戻すだけでよい。
        func place(_ normalized: CGPoint) -> CGPoint {
            CGPoint(
                x: extent.origin.x + normalized.x * extent.width,
                y: extent.origin.y + normalized.y * extent.height
            )
        }

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = source
        filter.topLeft = place(corners.topLeft)
        filter.topRight = place(corners.topRight)
        filter.bottomLeft = place(corners.bottomLeft)
        filter.bottomRight = place(corners.bottomRight)
        filter.crop = true

        guard let output = filter.outputImage else { return nil }
        let result = output.extent
        guard isUsable(extent: result), result.width >= 1, result.height >= 1 else { return nil }
        // 文字がつぶれるほど小さくなったら、直さないほうがまし。
        let correctedArea = Double(result.width) * Double(result.height)
        let sourceArea = Double(extent.width) * Double(extent.height)
        guard correctedArea >= sourceArea * minimumAreaRatio else { return nil }

        // CIContext は1枚ごとに作る。使い回すには別のところから同時に触らない
        // 約束が要るが、レシートは1枚ずつしか読まないので作り直しで足りる。
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(output, from: result)
    }
}
