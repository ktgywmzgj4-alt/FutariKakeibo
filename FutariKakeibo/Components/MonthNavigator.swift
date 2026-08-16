import SwiftUI

struct MonthNavigator: View {
    let month: Date
    let onMove: (Int) -> Void

    var body: some View {
        HStack {
            Button { onMove(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("前の月")

            Spacer()
            Text(month.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "ja_JP"))))
                .font(.headline)
                .foregroundStyle(AppTheme.deepGreen)
            Spacer()

            Button { onMove(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("次の月")
        }
        .foregroundStyle(AppTheme.terracotta)
    }
}
