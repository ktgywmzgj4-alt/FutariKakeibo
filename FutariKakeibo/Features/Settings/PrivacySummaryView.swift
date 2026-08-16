import SwiftUI

struct PrivacySummaryView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("レシート") {
                    privacyRow(
                        "端末内で読み取り",
                        detail: "撮影画像はOCRのためだけに使い、保存・共有・外部送信しません。",
                        icon: "doc.viewfinder"
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
                .foregroundStyle(AppTheme.sage)
        }
    }
}
