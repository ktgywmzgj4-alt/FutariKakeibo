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
