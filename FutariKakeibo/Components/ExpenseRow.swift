import SwiftUI

struct ExpenseRow: View {
    let expense: Expense
    let household: Household

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: expense.category.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(expense.category.color)
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(expense.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.deepGreen)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(expense.date.formatted(.dateTime.month().day()))
                    Text("•")
                    Text(household.member(id: expense.paidByMemberID)?.displayName ?? "不明")
                    if expense.splitMethod == .personal {
                        Text("個人")
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.sageSoft)
                            .clipShape(Capsule())
                    }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: 8)

            Text(expense.amount.yenText)
                .font(.body.monospacedDigit().weight(.bold))
                .foregroundStyle(AppTheme.deepGreen)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(expense.title)、\(expense.amount.yenText)、\(expense.category.displayName)、" +
            "\(household.member(id: expense.paidByMemberID)?.displayName ?? "不明")が支払い"
        )
    }
}
