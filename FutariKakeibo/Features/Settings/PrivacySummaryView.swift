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
                        detail: "iCloud共有を有効にしている場合、保存したレシート画像は共有に参加した人も見られます。参加していない人には渡りません。",
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
                        "共有するとiCloudへ",
                        detail: Self.householdSharingDetail,
                        icon: "icloud"
                    )
                    privacyRow(
                        "合言葉は1回・1日だけ",
                        detail: Self.inviteDetail,
                        icon: "person.2.badge.key.fill"
                    )
                }

                Section("通知") {
                    privacyRow(
                        "通知に金額は出さない",
                        detail: Self.notificationDetail,
                        icon: "bell.badge"
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

    /// 家計のデータを置く場所。公開データベースには置かない。
    static let householdSharingDetail =
        "共有を始めた場合だけ、家計のデータを家計簿を作った人のiCloud（CloudKit）に置き、共有に参加した人と同期します。家計のデータは公開データベースには置きません。"

    /// 合言葉を置く場所。2026-10-19 まで「公開データベースは使いません」と書いていたが、
    /// 合言葉は公開データベースに置いている（`CloudKitSyncService.publishInvite`）。
    static let inviteDetail =
        "合言葉を発行すると、共有の場所と期限だけを、CloudKitの公開データベース（アプリの利用者が合言葉を指定して読める場所）に一時的に置きます。家計のデータは置きません。合言葉は1回使われるか1日たつと使えなくなり、発行したiPhoneが次にアプリを開いたときに消します。合言葉を知っている人はだれでも参加できるので、相手にだけ伝えてください。"

    /// 相手の支出の通知（T-046）。通知の文は端末で作り、ロック画面に金額・店名を出さない。
    static let notificationDetail =
        "パートナーの支出の通知は、設定でONにしたときだけ、このiPhoneの中で作ります。ロック画面に金額や店名は出しません。"

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
