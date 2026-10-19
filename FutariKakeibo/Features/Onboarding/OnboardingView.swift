import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selfName = ""
    @State private var partnerName = ""
    @State private var budgetText = "100000"
    @FocusState private var focusedField: Field?

    private enum Field {
        case selfName
        case partnerName
        case budget
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 24)

                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 122, height: 122)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("ふたり家計簿")
                        .font(.largeTitle.bold())
                        .foregroundStyle(AppTheme.ink)
                    Text("お金の話を、やさしく、ふたりの日常に。")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("最初の設定")
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.ink)

                    labeledField("あなたの呼び名", text: $selfName, placeholder: "例：そら")
                        .textContentType(.nickname)
                        .focused($focusedField, equals: .selfName)

                    labeledField("パートナーの呼び名", text: $partnerName, placeholder: "例：つばさ")
                        .textContentType(.nickname)
                        .focused($focusedField, equals: .partnerName)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("2人の月予算")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                        TextField("100000", text: $budgetText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .budget)
                            .accessibilityLabel("2人の月予算")
                    }
                }
                .appCard()

                Button {
                    focusedField = nil
                    Task {
                        await store.createHousehold(
                            selfName: selfName,
                            partnerName: partnerName,
                            monthlyBudget: parsedBudget
                        )
                    }
                } label: {
                    Text("はじめる")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundStyle(.white)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(parsedBudget <= 0)
                .opacity(parsedBudget <= 0 ? 0.5 : 1)

                recoverySection

                Label(
                    "最初はこのiPhone内だけに保存します。iCloud共有は設定画面から、準備ができた時に有効にできます。",
                    systemImage: "lock.shield.fill"
                )
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.bottom, 30)
            }
            .padding(.horizontal, 22)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var parsedBudget: Int {
        Int(budgetText.filter(\.isNumber)) ?? 0
    }

    /// アプリを入れ直した人のための入口。
    ///
    /// **押したときだけiCloudを見に行く。** 起動時に見に行くと、iCloudの
    /// entitlementを持たないビルドで `CKException` が飛び、Swiftのcatchでは
    /// 捕まらずアプリごと落ちる。初めて開いた人を待たせないためでもある。
    @ViewBuilder
    private var recoverySection: some View {
        VStack(spacing: 10) {
            Button {
                focusedField = nil
                Task { await store.recoverHouseholdFromCloud() }
            } label: {
                HStack(spacing: 8) {
                    if store.isRecovering {
                        WalletSpinner(size: 20, label: "さがしています")
                    }
                    Text(store.isRecovering ? "さがしています…" : "以前の家計簿を取り戻す")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .foregroundStyle(AppTheme.accent)
                .background(AppTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(store.isRecovering)
            .accessibilityHint("このiPhoneで前に使っていた家計簿をiCloudから探します")

            if let outcome = store.recoveryOutcome {
                recoveryMessage(outcome)
            } else {
                Text(Self.recoveryHint)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private func recoveryMessage(_ outcome: AppStore.RecoveryOutcome) -> some View {
        switch outcome {
        case .recovered:
            // 取り戻せたときは画面そのものが入れ替わるので、ここはまず見えない。
            EmptyView()
        case .nothingFound:
            Text("このiCloudには家計簿が見つかりませんでした。iPhoneの中だけで使っていた家計簿は、アプリを削除すると戻せません。相手から合言葉をもらって参加するか、新しく始めてください。")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
        case .chooseOne:
            candidateList
        case let .failed(message):
            Text(message)
                .font(.caption)
                .foregroundStyle(AppTheme.warning)
                .multilineTextAlignment(.center)
        }
    }

    /// 取り戻せる家計簿が2つ以上あるときの選ぶ一覧。いちばん最近まで使われていたものが先頭。
    private var candidateList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("iCloudに家計簿が\(store.recoveryCandidates.count)つ見つかりました。いつも使っている家計簿を選んでください。選ばなかった家計簿もiCloudに残ります。")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            ForEach(store.recoveryCandidates) { candidate in
                Button {
                    Task { await store.recover(candidate) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.candidateTitle(candidate))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text(Self.candidateDetail(candidate))
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(store.isRecovering)
                .accessibilityHint("この家計簿をこのiPhoneに戻します")
            }
        }
    }

    /// 取り戻せるのは、同じApple IDで、iCloudに置いてあった家計簿だけ。
    /// 「このiPhoneを前にも使っていたなら」と書いていたが、iPhoneの中だけで使っていた家計簿は
    /// アプリを消すと戻せない。戻せない家計簿に「戻せます」と言わない（2026-10-19 監査）。
    static let recoveryHint = "同じApple IDで、合言葉を発行したり参加したりしてiCloudに置いてあった家計簿なら、"
        + "別のiPhoneからでも戻せます。iPhoneの中だけで使っていた家計簿は戻せません。"

    static func candidateTitle(_ candidate: RecoveryCandidate) -> String {
        let names = candidate.memberNames.joined(separator: "・")
        let side = candidate.isOwnHousehold ? "あなたが作った家計簿" : "相手から共有された家計簿"
        return names.isEmpty ? side : "\(names)（\(side)）"
    }

    static func candidateDetail(_ candidate: RecoveryCandidate) -> String {
        let date = candidate.lastActivity.formatted(date: .numeric, time: .omitted)
        return "支出\(candidate.expenseCount)件・収入\(candidate.incomeCount)件・最後の記録 \(date)"
    }

    private func labeledField(
        _ label: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(label)
        }
    }
}
