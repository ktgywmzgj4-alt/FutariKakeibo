import SwiftUI

struct PrivacySummaryView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("レシート") {
                    privacyRow(
                        "端末内で読み取り",
                        detail: "文字の読み取りはこのiPhoneの中だけで行い、外部のサーバーへは送りません。",
                        icon: "doc.viewfinder"
                    )
                    privacyRow(
                        "画像は縮小して保存",
                        detail: "「レシート画像を保存」がONのときだけ、縮小した1枚を残します。原寸の写真は残しません。",
                        icon: "photo.on.rectangle.angled"
                    )
                    privacyRow(
                        "共有中は相手も見られる",
                        detail: "iCloud共有を有効にしている場合、保存したレシート画像は招待した相手も見られます。それ以外の人には渡りません。",
                        icon: "person.2"
                    )
                    privacyRow(
                        "支出を消せば画像も消える",
                        detail: "支出を削除すると、その支出のレシート画像も、このiPhoneとiCloudの両方から消えます。",
                        icon: "trash"
                    )
                }

                Section("家計データ") {
                    privacyRow(
                        "最初はこのiPhone内",
                        detail: "ファイル保護を有効にして保存します。",
                        icon: "iphone"
                    )
                    privacyRow(
                        "共有は招待制",
                        detail: "iCloud共有を有効にした場合だけ、招待した参加者とCloudKit経由で同期します。公開データベースは使いません。",
                        icon: "person.2.badge.key.fill"
                    )
                }

                Section("利用しないもの") {
                    privacyRow("広告トラッキングなし", detail: "行動追跡SDKや広告IDは使いません。", icon: "hand.raised.slash.fill")
                    privacyRow("位置情報なし", detail: "現在地や移動履歴は取得しません。", icon: "location.slash.fill")
                    privacyRow("連絡先なし", detail: "アドレス帳にはアクセスしません。", icon: "person.crop.circle.badge.xmark")
                }

                Section {
                    Text("正式公開前に、運営者情報、問い合わせ先、保存期間、削除方法を含む公開用プライバシーポリシーURLが必要です。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .navigationTitle("データとプライバシー")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func privacyRow(_ title: String, detail: String, icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.positive)
        }
    }
}
