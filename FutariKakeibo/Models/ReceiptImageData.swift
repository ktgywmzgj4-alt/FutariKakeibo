import Foundation

/// 保存用に縮小・圧縮したあとのレシート画像。
///
/// ここを通るのは**常に圧縮後のバイト列**です。撮った原寸の画像は、
/// 読み取りが終わった時点で捨てます（`ReceiptImageProcessor`）。
/// 家計簿データ本体（`Expense`）にはこの型を入れません。支出が持つのは
/// `receiptImageID` だけで、実体はファイルとiCloudにあります。
struct ReceiptImageData: Sendable, Equatable {
    /// 詳細画面で見せる画像。長辺1600pxのJPEG。
    let display: Data
    /// 一覧で使う小さな画像。長辺240pxのJPEG。
    let thumbnail: Data
    let pixelWidth: Int
    let pixelHeight: Int

    init(display: Data, thumbnail: Data, pixelWidth: Int, pixelHeight: Int) {
        self.display = display
        self.thumbnail = thumbnail
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// 1枚あたりの容量。画面で「およそ何KB」と伝えるのに使う。
    var byteCount: Int { display.count + thumbnail.count }
}
