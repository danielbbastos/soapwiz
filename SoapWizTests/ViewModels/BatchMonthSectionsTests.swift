import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Grouping the history list by the month each batch was made in. The calendar
/// is pinned to UTC so month boundaries fall in the same place wherever the
/// suite runs.
@Suite("Batch month sections")
@MainActor
struct BatchMonthSectionsTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0,
        in calendar: Calendar? = nil
    ) throws -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return try #require((calendar ?? self.calendar).date(from: components))
    }

    private func batch(_ name: String, made date: Date) -> Batch {
        Batch(recipe: nil, recipeName: name, dateCreated: date, batchCount: 1)
    }

    private func sections(_ batches: [Batch]) -> [BatchMonthSection] {
        BatchHistoryViewModel.monthSections(batches, calendar: calendar)
    }

    @Test func monthSections_NoBatches_IsEmpty() {
        #expect(sections([]).isEmpty)
    }

    @Test func monthSections_BatchesInOneMonth_ShareOneSection() throws {
        let result = sections([
            batch("Castile", made: try date(2026, 9, 3)),
            batch("Bastille", made: try date(2026, 9, 28))
        ])

        #expect(result.count == 1)
        #expect(result.first?.month == (try date(2026, 9, 1, 0)))
        #expect(result.first?.batches.count == 2)
    }

    @Test func monthSections_SeveralMonths_NewestMonthFirst() throws {
        let result = sections([
            batch("July", made: try date(2026, 7, 15)),
            batch("September", made: try date(2026, 9, 15)),
            batch("August", made: try date(2026, 8, 15))
        ])

        #expect(result.map(\.month) == [try date(2026, 9, 1, 0), try date(2026, 8, 1, 0), try date(2026, 7, 1, 0)])
    }

    @Test func monthSections_WithinAMonth_NewestBatchFirst() throws {
        let result = sections([
            batch("Early", made: try date(2026, 9, 2)),
            batch("Late", made: try date(2026, 9, 29)),
            batch("Middle", made: try date(2026, 9, 15))
        ])

        #expect(result.first?.batches.map(\.recipeName) == ["Late", "Middle", "Early"])
    }

    @Test func monthSections_SameMonthInDifferentYears_AreSeparate() throws {
        let result = sections([
            batch("This year", made: try date(2026, 4, 10)),
            batch("Last year", made: try date(2025, 4, 10))
        ])

        #expect(result.map(\.month) == [try date(2026, 4, 1, 0), try date(2025, 4, 1, 0)])
    }

    @Test func monthSections_AcrossNewYear_JanuaryComesBeforeDecember() throws {
        let result = sections([
            batch("December", made: try date(2025, 12, 31)),
            batch("January", made: try date(2026, 1, 1))
        ])

        #expect(result.map { $0.batches.map(\.recipeName) } == [["January"], ["December"]])
    }

    @Test func monthSections_LastSecondAndFirstSecond_FallInTheirOwnMonths() throws {
        let result = sections([
            batch("Last second of August", made: try date(2026, 8, 31, 23, 59, 59)),
            batch("First second of September", made: try date(2026, 9, 1, 0, 0, 0))
        ])

        #expect(result.map { $0.batches.map(\.recipeName) } == [["First second of September"], ["Last second of August"]])
    }

    /// Half past eleven at night in UTC on 30 September is already October in
    /// Lisbon: the batch belongs to the month the maker saw on their clock.
    @Test func monthSections_TimeZone_DecidesTheMonth() throws {
        let made = try date(2026, 9, 30, 23, 30)
        var lisbon = Calendar(identifier: .gregorian)
        lisbon.timeZone = try #require(TimeZone(identifier: "Europe/Lisbon"))

        let inUTC = BatchHistoryViewModel.monthSections([batch("Late pour", made: made)], calendar: calendar)
        let inLisbon = BatchHistoryViewModel.monthSections([batch("Late pour", made: made)], calendar: lisbon)

        #expect(inUTC.first?.month == (try date(2026, 9, 1, 0)))
        #expect(inLisbon.first?.month == (try date(2026, 10, 1, 0, in: lisbon)))
    }
}
