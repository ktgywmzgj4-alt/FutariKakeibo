import SwiftUI

/// 追加タブ。支出と収入を切り替えて記録する。
struct EntryEditorView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case expense
        case income

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .expense: "支出"
            case .income: "収入"
            }
        }
    }

    let onSaved: () -> Void

    @State private var kind: Kind = .expense

    var body: some View {
        VStack(spacing: 0) {
            ScreenTitle(kind == .expense ? "支出を追加" : "収入を追加")
                .padding(.horizontal, 18)
                .padding(.top, 4)

            Picker("記録する種類", selection: $kind) {
                ForEach(Kind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 8)

            switch kind {
            case .expense:
                ExpenseEditorView(onSaved: onSaved)
            case .income:
                IncomeEditorView(onSaved: onSaved)
            }
        }
        .background(AppTheme.background)
    }
}
