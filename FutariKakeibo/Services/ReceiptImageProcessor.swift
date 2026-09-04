import UIKit

/// 撮ったレシートを、保存してよい大きさまで縮めて圧縮する。
///
/// 原寸のままだと1枚で数MBあり、2人分がiCloudにたまっていく。
/// **文字が読める範囲でいちばん軽い形**にしてから保存する。
/// 読み取り（OCR）は原寸に対して先に済ませてあるので、ここで縮めても
/// 読み取りの精度には影響しない。
enum ReceiptImageProcessor {
    /// 詳細画面で見る画像の長辺。レシートの小さな文字が読める下限がこのあたり。
    static let displayLongEdge: CGFloat = 1600
    /// 一覧に出す画像の長辺。
    static let thumbnailLongEdge: CGFloat = 240
    /// JPEGの画質。0.7でレシートの文字は読める。上げると容量だけ増える。
    static let displayQuality: CGFloat = 0.7
    static let thumbnailQuality: CGFloat = 0.6

    /// 縮小と圧縮はバックグラウンドで行う。画面を止めない。
    ///
    /// 画像そのものは戻さず、圧縮済みのバイト列だけを返す。
    /// これで呼び出し側は原寸の画像を持ち続けずに済む。
    static func process(image: UIImage) async -> ReceiptImageData? {
        guard let cgImage = image.cgImage else { return nil }
        let orientation = image.imageOrientation
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: make(cgImage: cgImage, orientation: orientation))
            }
        }
    }

    /// 長辺を上限に合わせた大きさ。元が上限より小さいときは拡大しない。
    static func fittedSize(for size: CGSize, maxLongEdge: CGFloat) -> CGSize {
        let longEdge = max(size.width, size.height)
        guard longEdge > 0 else { return CGSize(width: 1, height: 1) }
        guard longEdge > maxLongEdge else {
            return CGSize(
                width: max(1, size.width.rounded()),
                height: max(1, size.height.rounded())
            )
        }
        let ratio = maxLongEdge / longEdge
        return CGSize(
            width: max(1, (size.width * ratio).rounded()),
            height: max(1, (size.height * ratio).rounded())
        )
    }

    private static func make(cgImage: CGImage, orientation: UIImage.Orientation) -> ReceiptImageData? {
        // 写真は撮った向きの情報を別に持っている。向きを渡さずに描くと横倒しで保存される。
        let source = UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
        guard
            let display = resized(source, maxLongEdge: displayLongEdge),
            let displayData = display.jpegData(compressionQuality: displayQuality),
            let thumbnail = resized(source, maxLongEdge: thumbnailLongEdge),
            let thumbnailData = thumbnail.jpegData(compressionQuality: thumbnailQuality)
        else {
            return nil
        }
        return ReceiptImageData(
            display: displayData,
            thumbnail: thumbnailData,
            pixelWidth: Int(display.size.width.rounded()),
            pixelHeight: Int(display.size.height.rounded())
        )
    }

    private static func resized(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage? {
        let target = fittedSize(for: image.size, maxLongEdge: maxLongEdge)
        let format = UIGraphicsImageRendererFormat.preferred()
        // 画面の倍率を掛けない。1600pxと言ったら1600pxで作る。
        format.scale = 1
        // レシートは白地。透明を持たせないほうが軽い。
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
