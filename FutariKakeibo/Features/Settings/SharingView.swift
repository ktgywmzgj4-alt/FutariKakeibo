import SwiftUI
import UIKit

/// 合言葉ひとつで家計簿を2人で共有する画面。
struct SharingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var enteredCode = ""
    @State private var didJoin = false
    @State private var confirmStopSharing = false
    @FocusState private var codeFieldFocused: Bool

    private var isShared: Bool { store.household?.cloudLocation != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.cardSpacing) {
                stateCard
                if isShared, let members = store.shareMembers {
                    membersCard(members)
                }
                if let invite = store.shareInvite {
                    codeCard(invite)
                } else {
                    if store.inviteWasUsed {
                        usedNotice
                    }
                    inviteCard
                }
                joinCard
                noticeCard
            }
            .padding(AppTheme.screenPadding)
            .padding(.bottom, 26)
        }
        .background(AppTheme.background)
        .task {
            // 誰が参加しているかを読み、使われた・期限の切れた合言葉を片付ける。
            await store.loadShareMembers()
            await store.tidyIssuedInvites()
        }
        .confirmationDialog(
            "共有をやめますか？",
            isPresented: $confirmStopSharing,
            titleVisibility: .visible
        ) {
            Button("共有をやめる", role: .destructive) {
                Task { await store.stopSharingBecauseOfStrangers() }
            }
            Button("やめない", role: .cancel) {}
        } message: {
            Text(Self.stopSharingMessage)
        }
        .navigationTitle("ふたりで共有")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") { codeFieldFocused = false }
            }
        }
        .alert("参加しました", isPresented: $didJoin) {
            Button("わかりました", role: .cancel) {}
        } message: {
            Text("相手の家計簿に入りました。これからは2人の記録がiCloud経由でそろいます。")
        }
    }

    private var stateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 印と色は**同期の状態**に合わせる。共有しているかどうかで決めていたため、
            // 「同期できませんでした」の横に緑のチェックが出ていた。
            Label(store.syncState.label, systemImage: stateIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(stateColor)

            // iCloudに置いてあることと、相手が参加済みであることは別。
            // 誰も招いていないうちから「2人で共有しています」と言わない。
            Text(isShared
                 ? "この家計簿はiCloudに保存されています。合言葉を伝えた相手が参加すると、どちらが記録してももう一方の端末に届きます。"
                 : "いまはこのiPhoneの中だけに保存しています。アプリを削除すると、この家計簿は戻せません。合言葉を発行すると、iCloudにも保存され、相手と同じ家計簿を使えます。")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var stateIcon: String {
        switch store.syncState {
        case .localOnly: "iphone"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .synced: "checkmark.icloud.fill"
        case .failed: "exclamationmark.icloud.fill"
        }
    }

    private var stateColor: Color {
        switch store.syncState {
        case .localOnly, .syncing: AppTheme.secondaryText
        case .synced: AppTheme.positive
        case .failed: AppTheme.danger
        }
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("相手を招く", systemImage: "person.badge.plus")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            Text("合言葉を発行して相手に伝えてください。相手がこの画面で入力すると、同じ家計簿に入れます。")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)

            Button {
                Task { await store.startSharingWithCode() }
            } label: {
                if store.isPreparingInvite {
                    WalletSpinner(size: 22, label: "iCloudとやりとり中")
                        .frame(maxWidth: .infinity)
                } else {
                    Text("合言葉を発行する")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(AppTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .disabled(store.isPreparingInvite)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private func codeCard(_ invite: ShareInvite) -> some View {
        VStack(spacing: 14) {
            Text("この合言葉を相手に伝えてください")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)

            Text(invite.formattedCode)
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.ink)
                .textSelection(.enabled)
                .accessibilityLabel(invite.code.map { String($0) }.joined(separator: " "))

            Text(invite.remainingDescription)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)

            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = invite.formattedCode
                } label: {
                    Label("コピー", systemImage: "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .foregroundStyle(AppTheme.accent)
                .background(AppTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                ShareLink(item: "ふたり家計簿の合言葉：\(invite.formattedCode)") {
                    Label("送る", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .foregroundStyle(AppTheme.accent)
                .background(AppTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }

            Button("新しい合言葉を発行する") {
                Task { await store.startSharingWithCode() }
            }
            .font(.footnote)
            .foregroundStyle(AppTheme.secondaryText)
            .disabled(store.isPreparingInvite)
        }
        .frame(maxWidth: .infinity)
        .appCard()
    }

    /// 共有に参加している人。ふたりより多ければ知らせる。
    private func membersCard(_ members: [CloudKitSyncService.ShareMember]) -> some View {
        let joined = members.filter { $0.isOwner || $0.hasAccepted }
        let strangers = CloudKitSyncService.strangerCount(in: members)
        let isOwner = store.household?.cloudLocation?.scope == .privateDatabase
        return VStack(alignment: .leading, spacing: 9) {
            Label("参加している人（\(joined.count)人）", systemImage: "person.2")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)

            ForEach(Array(joined.enumerated()), id: \.offset) { _, member in
                Text(Self.memberLine(member))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            if strangers > 0 {
                Text("ふたりより多く参加しています（\(strangers)人多い）。合言葉やリンクが知らない人に渡った可能性があります。")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.danger)
                if isOwner {
                    Button("共有をやめる（全員が外れます）") { confirmStopSharing = true }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.danger)
                        .disabled(store.isPreparingInvite)
                } else {
                    Text("この家計簿を作った人に知らせて、共有をやめてもらってください。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    /// 共有をやめる前の確認。**「やめれば前のリンクで入れなくなる」とは言わない。**
    /// 共有を始め直すと、共有のリンクは前と同じになる（Appleの `CKShare.url` の説明）。
    static let stopSharingMessage =
        "パートナーも含めて、参加している人は全員この家計簿に入れなくなります。家計簿の記録は消えません。"
        + "続けて使うときは、新しい合言葉でパートナーに入り直してもらってください。"
        + "共有のリンクは前と同じなので、リンクそのものを控えている人はまた入れます。そのときもここに人数が出ます。"

    static func memberLine(_ member: CloudKitSyncService.ShareMember) -> String {
        let name = member.name ?? "（名前は表示されません）"
        var tags: [String] = []
        if member.isOwner { tags.append("作った人") }
        if member.isCurrentUser { tags.append("あなた") }
        return tags.isEmpty ? "・\(name)" : "・\(name)（\(tags.joined(separator: "・"))）"
    }

    private var usedNotice: some View {
        Label("合言葉が使われました。相手がこの家計簿に参加しています。", systemImage: "checkmark.circle")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppTheme.positive)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard()
    }

    private var joinCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("相手の家計簿に入る", systemImage: "key.horizontal")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            Text("相手が発行した合言葉を入力してください。")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)

            TextField("ABCD-2345", text: $enteredCode)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($codeFieldFocused)
                .padding(.vertical, 13)
                .background(AppTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(AppTheme.line, lineWidth: 1)
                )

            Button {
                codeFieldFocused = false
                Task {
                    if await store.joinSharing(code: enteredCode) {
                        enteredCode = ""
                        didJoin = true
                    }
                }
            } label: {
                if store.isPreparingInvite {
                    WalletSpinner(size: 22, label: "iCloudとやりとり中")
                        .frame(maxWidth: .infinity)
                } else {
                    Text("この合言葉で参加する")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(canJoin ? AppTheme.positive : AppTheme.secondaryText.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .disabled(!canJoin)

            if isShared {
                Text("いま使っている家計簿は置き換わります。手元の記録は共有先のものに切り替わるので、必要ならCSVで書き出してから参加してください。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.danger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var noticeCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("合言葉について", systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)

            bullet("合言葉には家計のデータは入っていません。どの家計簿に入るかを示すだけです。")
            bullet("合言葉は、iCloudの公開データベース（このアプリの利用者なら、合言葉を指定して読める場所）に、家計簿の場所と期限だけを入れて一時的に置きます。使われたら、発行したiPhoneが次にアプリを開いたときに消します。")
            bullet("1日で使えなくなります。誰かが1回参加すると、その合言葉はもう使えません。")
            bullet("合言葉を知っている人は誰でも参加できます。相手にだけ伝えてください。")
            bullet("家計のデータはAppleのiCloudに保存され、この家計簿に参加した人だけが読み書きできます。")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text("・")
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(AppTheme.secondaryText)
    }

    private var canJoin: Bool {
        ShareInvite.isComplete(enteredCode) && !store.isPreparingInvite
    }
}
