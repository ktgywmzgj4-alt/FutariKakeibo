import CryptoKit
import Foundation

/// 定期支出のひな形から、実際の支出を「まだ作られていない月の分だけ」作る。
///
/// 生成する支出のIDは、ひな形IDと対象年月から必ず同じ値になるよう決めている。
/// これにより2台の端末が別々に同じ月を展開しても重複が生まれず、利用者が消した回は
/// 削除印（deletedExpenseIDs）に残るため復活しない。
enum RecurringExpenseScheduler {
    /// 初回起動や長期間の放置で過去を無限にさかのぼらないための上限。
    static let maximumBackfillMonths = 24

    /// 未生成の支出を返す。同じ入力なら常に同じ結果になる。
    static func pendingExpenses(
        templates: [RecurringExpense],
        existing: [Expense],
        deletedExpenseIDs: Set<UUID>,
        upTo referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> [Expense] {
        let existingIDs = Set(existing.map(\.id))
        var generated: [Expense] = []

        for template in templates where template.isActive && template.isValid {
            for month in months(for: template, upTo: referenceDate, calendar: calendar) {
                guard
                    let occurrence = occurrenceDate(for: template, in: month, calendar: calendar),
                    occurrence <= referenceDate
                else { continue }

                let id = expenseID(templateID: template.id, month: month, calendar: calendar)
                guard !existingIDs.contains(id), !deletedExpenseIDs.contains(id) else { continue }

                generated.append(
                    Expense(
                        id: id,
                        title: template.title,
                        amount: template.amount,
                        date: occurrence,
                        category: template.category,
                        paidByMemberID: template.paidByMemberID,
                        splitMethod: template.splitMethod,
                        note: template.note,
                        recurringID: template.id,
                        createdAt: occurrence,
                        updatedAt: occurrence
                    )
                )
            }
        }

        return generated.sorted { $0.date < $1.date }
    }

    /// 予定として表示する、ひな形と計上日の組。
    struct Occurrence: Identifiable, Equatable, Sendable {
        var template: RecurringExpense
        var date: Date

        var id: UUID { template.id }
    }

    /// 指定した月に、これから計上される予定のひな形と日付を返す。ホーム画面の予告に使う。
    static func upcomingOccurrences(
        templates: [RecurringExpense],
        in month: Date,
        after referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> [Occurrence] {
        templates
            .filter { $0.isActive && $0.isValid }
            .compactMap { template -> Occurrence? in
                guard
                    isMonthCovered(template, month: month, calendar: calendar),
                    let occurrence = occurrenceDate(for: template, in: month, calendar: calendar),
                    occurrence > referenceDate
                else { return nil }
                return Occurrence(template: template, date: occurrence)
            }
            .sorted { $0.date < $1.date }
    }

    /// ひな形が指定月に計上される日。月末が短い月は最終日へ寄せる。
    static func occurrenceDate(
        for template: RecurringExpense,
        in month: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard
            let startOfMonth = calendar.startOfMonth(for: month),
            let range = calendar.range(of: .day, in: .month, for: startOfMonth)
        else { return nil }
        let day = min(max(template.dayOfMonth, RecurringExpense.minimumDayOfMonth), range.count)
        return calendar.date(byAdding: .day, value: day - 1, to: startOfMonth)
    }

    /// ひな形IDと年月から決まる支出ID。端末が違っても同じ値になる。
    static func expenseID(
        templateID: UUID,
        month: Date,
        calendar: Calendar = .current
    ) -> UUID {
        let components = calendar.dateComponents([.year, .month], from: month)
        let year = components.year ?? 0
        let monthNumber = components.month ?? 0
        return expenseID(templateID: templateID, year: year, month: monthNumber)
    }

    static func expenseID(templateID: UUID, year: Int, month: Int) -> UUID {
        var hasher = SHA256()
        hasher.update(data: Data(templateID.uuidString.lowercased().utf8))
        hasher.update(data: Data(String(format: "|%04d-%02d", year, month).utf8))
        var bytes = Array(hasher.finalize().prefix(16))
        // RFC 4122のversion 5 / variantビットへ揃え、通常のUUIDと衝突しない形にする。
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            )
        )
    }

    // MARK: - Private

    private static func months(
        for template: RecurringExpense,
        upTo referenceDate: Date,
        calendar: Calendar
    ) -> [Date] {
        guard
            let referenceMonth = calendar.startOfMonth(for: referenceDate),
            let startMonth = calendar.startOfMonth(for: template.startMonth)
        else { return [] }

        let earliest = calendar.date(
            byAdding: .month,
            value: -maximumBackfillMonths,
            to: referenceMonth
        ) ?? referenceMonth

        var limit = referenceMonth
        if let endMonth = template.endMonth,
           let normalizedEnd = calendar.startOfMonth(for: endMonth) {
            limit = min(limit, normalizedEnd)
        }

        var current = max(startMonth, earliest)
        var months: [Date] = []
        while current <= limit {
            months.append(current)
            guard let next = calendar.date(byAdding: .month, value: 1, to: current) else { break }
            current = next
        }
        return months
    }

    private static func isMonthCovered(
        _ template: RecurringExpense,
        month: Date,
        calendar: Calendar
    ) -> Bool {
        guard
            let target = calendar.startOfMonth(for: month),
            let startMonth = calendar.startOfMonth(for: template.startMonth)
        else { return false }
        if target < startMonth { return false }
        if let endMonth = template.endMonth,
           let normalizedEnd = calendar.startOfMonth(for: endMonth),
           target > normalizedEnd {
            return false
        }
        return true
    }
}
