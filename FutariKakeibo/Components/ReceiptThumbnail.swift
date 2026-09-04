import SwiftUI
import UIKit

/// 一覧の行に出す、レシートがある印。
///
/// 端末内に小さな画像があればそれを、無ければアイコンを出す。
/// **ここからiCloudへ取りには行きません。** 一覧をめくるたびに通信すると重くなるためです。
/// 相手が撮ったレシートは、詳細画面を一度開けばこの端末にも残り、次から絵が出ます。
struct ReceiptThumbnail: View {
    @EnvironmentObject private var store: AppStore

    let imageID: UUID
    var size: CGFloat = 22

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(AppTheme.accentSoft)
                Image(systemName: "doc.text.image")
                    .font(.system(size: size * 0.6, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityLabel("レシートあり")
        // 行が画面の外へ出れば、この読み込みは打ち切られる。
        .task(id: imageID) {
            guard let data = await store.receiptThumbnail(for: imageID) else { return }
            image = UIImage(data: data)
        }
    }
}
