import SwiftUI
import UIKit

/// 合言葉ひとつで家計簿を2人で共有する画面。
struct SharingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var enteredCode = ""
    @State private var didJoin = false
    @FocusState private var codeFieldFocused: Bool

    private var isShared: Bool { store.household?.cloudLocation != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.cardSpacing) {
                stateCard
                if let invite = store.shareInvite {
                    codeCard(invite)
                } else {
                    inviteCard
                }
                joinCard
                noticeCard
            }
            .padding(AppTheme.screenPadding)
            .padding(.bottom, 26)
        }
        .background(AppTheme.background)
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
            Label(store.syncState.label, systemImage: isShared ? "checkmark.icloud.fill" : "iphone")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isShared ? AppTheme.positive : AppTheme.secondaryText)

            Text(isShared
                 ? "この家計簿は2人で共有しています。どちらが記録しても、もう一方の端末に届きます。"
                 : "いまはこのiPhoneの中だけに保存しています。合言葉を発行すると、相手と同じ家計簿を使えます。")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
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
                    ProgressView().frame(maxWidth: .infinity)
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
                    ProgressView().frame(maxWidth: .infinity)
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
            bullet("1日で使えなくなります。")
            bullet("誰かが参加すると、その合言葉は無効になります。")
            bullet("家計のデータはAppleのiCloudに保存され、招いた相手だけが読み書きできます。")
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
