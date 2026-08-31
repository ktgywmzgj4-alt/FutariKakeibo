import XCTest
@testable import FutariKakeibo

final class RecurringExpenseSchedulerTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        return calendar
    }()

    private let payerID = UUID()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    private func template(
        id: UUID = UUID(),
        amount: Int = 80_000,
        dayOfMonth: Int = 25,
        start: Date,
        end: Date? = nil,
        isActive: Bool = true
    ) -> RecurringExpense {
        RecurringExpense(
            id: id,
            title: "家賃",
            amount: amount,
            category: .household,
            paidByMemberID: payerID,
            dayOfMonth: dayOfMonth,
            startMonth: start,
            endMonth: end,
            isActive: isActive,
            calendar: calendar
        )
    }

    func testGeneratesOneExpensePerMonthUpToToday() {
        let generated = RecurringExpenseScheduler.pendingExpenses(
            templates: [template(start: date(2026, 6, 1))],
            existing: [],
            deletedExpenseIDs: [],
            upTo: date(2026, 8, 26),
            calendar: calendar
        )

        XCTAssertEqual(generated.count, 3)
        XCTAssertEqual(generated.map(\.date), [
            date(2026, 6, 25),
            date(2026, 7, 25),
            date(2026, 8, 25)
        ])
        XCTAssertTrue(generated.allSatisfy { $0.amount == 80_000 })
        XCTAssertTrue(generated.allSatisfy(\.isRecurring))
    }

    func testDoesNotGenerateBeforeTheDayArrives() {
        let generated = RecurringExpenseScheduler.pendingExpenses(
            templates: [template(start: date(2026, 8, 1))],
            existing: [],
            deletedExpenseIDs: [],
            upTo: date(2026, 8, 24),
            calendar: calendar
        )

        XCTAssertTrue(generated.isEmpty)
    }

    func testRunningTwiceDoesNotDuplicate() {
        let templates = [template(start: date(2026, 7, 1))]
        let first = RecurringExpenseScheduler.pendingExpenses(
            templates: templates,
            existing: [],
            deletedExpenseIDs: [],
            upTo: date(2026, 8, 26),
            calendar: calendar
        )
        let second = RecurringExpenseScheduler.pendingExpenses(
            templates: templates,
            existing: first,
            deletedExpenseIDs: [],
            upTo: date(2026, 8, 26),
            calendar: calendar
        )

        XCTAssertEqual(first.count, 2)
        XCTAssertTrue(second.isEmpty)
    }

    func testDeletedOccurrenceIsNotRecreated() {
        let templates = [template(start: date(2026, 7, 1))]
        let generated = RecurringExpenseScheduler.pendingExpenses(
            templates: templates,
            existing: [],
            deletedExpenseIDs: [],
            upTo: date(2026, 8, 26),
            calendar: calendar
        )
        guard let removed = generated.first else { return XCTFail("生成されていない") }

        let regenerated = RecurringExpenseScheduler.pendingExpenses(
            templates: templates,
            existing: generated.filter { $0.id != removed.id },
            deletedExpenseIDs: [removed.id],
            upTo: date(2026, 8, 26),
            calendar: calendar
        )

        XCTAssertTrue(regenerated.isEmpty)
    }

    func testSameTemplateAndMonthAlwaysMakesTheSameID() {
        let templateID = UUID()
        let first = RecurringExpenseScheduler.expenseID(templateID: templateID, year: 2026, month: 8)
        let second = RecurringExpenseScheduler.expenseID(templateID: templateID, year: 2026, month: 8)
        let otherMonth = RecurringExpenseScheduler.expenseID(templateID: templateID, year: 2026, month: 9)
        let otherTemplate = RecurringExpenseScheduler.expenseID(templateID: UUID(), year: 2026, month: 8)

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, otherMonth)
        XCTAssertNotEqual(first, otherTemplate)
    }

    func testShortMonthUsesTheLastDay() {
        let generated = RecurringExpenseScheduler.pendingExpenses(
            templates: [template(dayOfMonth: 31, start: date(2026, 2, 1))],
            existing: [],
            deletedExpenseIDs: [],
            upTo: date(2026, 3, 1),
            calendar: calendar
        )

        XCTAssertEqual(generated.map(\.date), [date(2026, 2, 28)])
    }

    func testStoppedAndEndedTemplatesAreSkipped() {
        let stopped = template(start: date(2026, 6, 1), isActive: false)
        let ended = template(start: date(2026, 6, 1), end: date(2026, 7, 1))

        let stoppedResult = RecurringExpenseScheduler.pendingExpenses(
            templates: [stopped],
            existing: [],
            deletedExpenseIDs: [],
            upTo: date(2026, 8, 26),
            calendar: calendar
        )
        let endedResult = RecurringExpenseScheduler.pendingExpenses(
            templates: [ended],
            existing: [],
            deletedExpenseIDs: [],
            upTo: date(2026, 8, 26),
            calendar: calendar
        )

        XCTAssertTrue(stoppedResult.isEmpty)
        XCTAssertEqual(endedResult.map(\.date), [date(2026, 6, 25), date(2026, 7, 25)])
    }

    func testBackfillIsLimitedToTwoYears() {
        let generated = RecurringExpenseScheduler.pendingExpenses(
            templates: [template(dayOfMonth: 1, start: date(2015, 1, 1))],
            existing: [],
            deletedExpenseIDs: [],
            upTo: date(2026, 8, 26),
            calendar: calendar
        )

        XCTAssertEqual(generated.count, RecurringExpenseScheduler.maximumBackfillMonths + 1)
        XCTAssertEqual(generated.first?.date, date(2024, 8, 1))
    }

    func testUpcomingOccurrencesOnlyLooksForward() {
        let occurrences = RecurringExpenseScheduler.upcomingOccurrences(
            templates: [template(start: date(2026, 1, 1))],
            in: date(2026, 8, 1),
            after: date(2026, 8, 10),
            calendar: calendar
        )

        XCTAssertEqual(occurrences.map(\.date), [date(2026, 8, 25)])
    }
}
