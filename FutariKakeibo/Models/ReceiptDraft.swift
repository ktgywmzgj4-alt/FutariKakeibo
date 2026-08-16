import Foundation

struct ReceiptDraft: Equatable, Sendable {
    var merchant: String
    var amount: Int?
    var date: Date?
    var suggestedCategory: ExpenseCategory
    var recognizedText: String

    static let empty = ReceiptDraft(
        merchant: "",
        amount: nil,
        date: nil,
        suggestedCategory: .other,
        recognizedText: ""
    )
}
