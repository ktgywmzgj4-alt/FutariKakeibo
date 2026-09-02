import SwiftUI

struct IncomeRow: View {
    let income: Income
    let household: Household

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: income.source.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(AppTheme.positive)
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(income.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(income.date.formatted(.dateTime.month().day()))
                    Text("•")
                    Text(household.member(id: income.receivedByMemberID)?.displayName ?? "不明")
                    Text(income.source.displayName)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.positiveSoft)
                        .clipShape(Capsule())
                }
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: 8)

            Text("+" + income.amount.yenText)
                .font(.body.monospacedDigit().weight(.bold))
                .foregroundStyle(AppTheme.positive)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(income.title)、\(income.amount.yenText)、\(income.source.displayName)、" +
            "\(household.member(id: income.receivedByMemberID)?.displayName ?? "不明")が受け取り"
        )
    }
}
