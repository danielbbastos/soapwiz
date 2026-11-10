import Testing
import Foundation
@testable import SoapWiz

/// The batch heatmap's weeks, month columns, strip and range text (SW-365).
@Suite("Batch heatmap")
@MainActor
struct BatchHeatmapTests {

    private let calendar: Calendar

    init() throws {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Lisbon"))
        calendar.locale = Locale(identifier: "en_US")
        self.calendar = calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        )))
    }

    private func heatmap(now: Date, dates: [Date] = []) -> BatchHeatmap {
        BatchHeatmap(dates: dates, now: now, calendar: calendar)
    }

    // MARK: Window

    @Test func weeks_Always_AreFiftyTwoOldestFirst() throws {
        let result = heatmap(now: try date(2026, 11, 10, 15))
        #expect(result.weeks.count == 52)
        #expect(result.weeks == result.weeks.sorted { $0.start < $1.start })
    }

    @Test func weeks_MidWeek_WindowEndsWithCurrentMondayWeek() throws {
        let result = heatmap(now: try date(2026, 11, 10, 15))
        #expect(result.weeks.last?.start == (try date(2026, 11, 9)))
        #expect(result.weeks.last?.end == (try date(2026, 11, 15)))
        #expect(result.weeks.first?.start == (try date(2025, 11, 17)))
    }

    @Test func weeks_NextMonday_WindowRollsByOneWeek() throws {
        let result = heatmap(now: try date(2026, 11, 16, 9))
        #expect(result.weeks.last?.start == (try date(2026, 11, 16)))
        #expect(result.weeks.first?.start == (try date(2025, 11, 24)))
    }

    @Test func weeks_Sunday_BelongToTheWeekThatEndsThatDay() throws {
        let result = heatmap(now: try date(2026, 11, 15, 23, 59))
        #expect(result.weeks.last?.start == (try date(2026, 11, 9)))
    }

    // MARK: Counting

    @Test func count_MondayStartAndSundayEnd_LandInTheWeek() throws {
        let dates = [try date(2026, 11, 2, 0, 0), try date(2026, 11, 8, 23, 59)]
        let result = heatmap(now: try date(2026, 11, 10), dates: dates)
        let week = try #require(result.weeks.first { $0.start == (try? date(2026, 11, 2)) })
        #expect(week.count == 2)
        #expect(result.total == 2)
    }

    @Test func count_NextMondayMidnight_BelongsToTheNextWeek() throws {
        let result = heatmap(now: try date(2026, 11, 10), dates: [try date(2026, 11, 9, 0, 0)])
        #expect(result.weeks.last?.count == 1)
        #expect(result.weeks[50].count == 0)
    }

    @Test func count_OutsideWindow_IsIgnored() throws {
        let now = try date(2026, 11, 10)
        let before = try date(2025, 11, 16, 23, 59)
        let after = try date(2026, 11, 16, 0, 0)
        let result = heatmap(now: now, dates: [before, after])
        #expect(result.total == 0)
        #expect(result.weeks.allSatisfy { $0.count == 0 })
    }

    @Test func total_EqualsSumOfWeekCounts() throws {
        let dates = [
            try date(2026, 11, 9), try date(2026, 11, 10), try date(2026, 10, 1),
            try date(2026, 1, 1), try date(2020, 1, 1)
        ]
        let result = heatmap(now: try date(2026, 11, 10), dates: dates)
        #expect(result.total == 4)
        #expect(result.total == result.weeks.map(\.count).reduce(0, +))
    }

    @Test func level_Counts_MapToFourShades() {
        #expect(BatchHeatmap.level(for: 0) == 0)
        #expect(BatchHeatmap.level(for: 1) == 1)
        #expect(BatchHeatmap.level(for: 2) == 2)
        #expect(BatchHeatmap.level(for: 3) == 3)
        #expect(BatchHeatmap.level(for: 9) == 3)
    }

    @Test func empty_NoBatches_HasZeroTotal() throws {
        let result = heatmap(now: try date(2026, 11, 10))
        #expect(result.total == 0)
        #expect(result.weeks.count == 52)
    }

    // MARK: Month columns

    @Test func months_NovemberWindow_HasThirteenColumns() throws {
        let result = heatmap(now: try date(2026, 11, 10))
        #expect(result.months.count == 13)
        #expect(result.months.map(\.weeks.count).reduce(0, +) == 52)
    }

    @Test func months_EdgeColumns_ArePartial() throws {
        let result = heatmap(now: try date(2026, 11, 10))
        let first = try #require(result.months.first)
        let last = try #require(result.months.last)
        #expect(first.monthStart == (try date(2025, 11, 1)))
        #expect(first.weeks.map(\.start) == [try date(2025, 11, 17), try date(2025, 11, 24)])
        #expect(last.monthStart == (try date(2026, 11, 1)))
        #expect(last.weeks.map(\.start) == [try date(2026, 11, 2), try date(2026, 11, 9)])
    }

    @Test func months_PartialFirstMonth_WeeksSitAtTheirMondayOrdinal() throws {
        let result = heatmap(now: try date(2026, 11, 10))
        #expect(result.months.first?.weeks.map(\.row) == [2, 3])
        #expect(result.months.last?.weeks.map(\.row) == [0, 1])
    }

    @Test func months_WindowStartsLaterInMonth_LeavesRowsAboveEmpty() throws {
        let result = heatmap(now: try date(2026, 12, 8))
        let first = try #require(result.months.first)
        #expect(first.monthStart == (try date(2025, 12, 1)))
        #expect(first.weeks.map(\.start) == [try date(2025, 12, 15), try date(2025, 12, 22), try date(2025, 12, 29)])
        #expect(first.weeks.map(\.row) == [2, 3, 4])
        #expect(!first.weeks.contains { $0.row < 2 })
    }

    @Test func months_WindowStartsOnFirstMonday_FillsFromRowZero() throws {
        let result = heatmap(now: try date(2026, 11, 24))
        let first = try #require(result.months.first)
        #expect(first.weeks.first?.start == (try date(2025, 12, 1)))
        #expect(first.weeks.map(\.row) == [0, 1, 2, 3, 4])
        #expect(result.rowCount == 5)
    }

    @Test func months_FiveMondayMonth_HasFiveRows() throws {
        let result = heatmap(now: try date(2026, 11, 10))
        let december = try #require(result.months.first { $0.monthStart == (try? date(2025, 12, 1)) })
        let january = try #require(result.months.first { $0.monthStart == (try? date(2026, 1, 1)) })
        #expect(december.weeks.count == 5)
        #expect(january.weeks.count == 4)
        #expect(result.rowCount == 5)
    }

    @Test func months_WeeksBelongToTheMonthOfTheirMonday() throws {
        let result = heatmap(now: try date(2026, 11, 10))
        let straddling = try date(2026, 8, 31)
        let august = try #require(result.months.first { $0.monthStart == (try? date(2026, 8, 1)) })
        #expect(august.weeks.last?.start == straddling)
        #expect(august.weeks.last?.end == (try date(2026, 9, 6)))
    }

    @Test func months_Initial_IsTheVeryShortMonthSymbol() throws {
        let result = heatmap(now: try date(2026, 11, 10))
        #expect(result.months.first?.initial == calendar.veryShortMonthSymbols[10])
    }

    // MARK: Strip

    @Test func strip_Always_IsTwoRowsOfTwentySix() throws {
        let result = heatmap(now: try date(2026, 11, 10))
        #expect(result.strip.count == 2)
        #expect(result.strip.allSatisfy { $0.count == 26 })
        #expect(result.strip[0].first == result.weeks[0])
        #expect(result.strip[1].first == result.weeks[26])
        #expect(result.strip[1].last == result.weeks[51])
    }

    // MARK: Calendar edge cases

    @Test func weeks_WindowCoveringIsoWeek53_AreConsecutive() throws {
        let result = heatmap(now: try date(2027, 3, 1))
        #expect(result.weeks.count == 52)
        #expect(result.weeks.contains { $0.start == (try? date(2026, 12, 28)) })
        let week53 = try #require(result.weeks.first { $0.start == (try? date(2026, 12, 28)) })
        #expect(calendar.component(.weekOfYear, from: week53.start) == 53)
        for (previous, next) in zip(result.weeks, result.weeks.dropFirst()) {
            let days = calendar.dateComponents([.day], from: previous.start, to: next.start).day
            #expect(days == 7)
        }
        #expect(Set(result.weeks.map(\.id)).count == 52)
    }

    @Test func weeks_AcrossDaylightSavingChanges_StartAtLocalMidnightMonday() throws {
        for now in [try date(2026, 4, 1), try date(2026, 11, 10)] {
            let result = heatmap(now: now)
            for week in result.weeks {
                #expect(calendar.component(.weekday, from: week.start) == 2)
                #expect(calendar.component(.hour, from: week.start) == 0)
                #expect(calendar.component(.minute, from: week.start) == 0)
                #expect(calendar.component(.weekday, from: week.end) == 1)
            }
        }
    }

    @Test func count_SundayNightOfDaylightSavingChange_StaysInItsWeek() throws {
        let result = heatmap(now: try date(2026, 4, 1), dates: [try date(2026, 3, 29, 23, 30), try date(2026, 3, 30, 0, 30)])
        let before = try #require(result.weeks.first { $0.start == (try? date(2026, 3, 23)) })
        let after = try #require(result.weeks.first { $0.start == (try? date(2026, 3, 30)) })
        #expect(before.count == 1)
        #expect(after.count == 1)
    }

    // MARK: Range text

    @Test func rangeText_SameMonthInCurrentYear_OmitsYear() throws {
        let result = heatmap(now: try date(2026, 11, 10))
        #expect(result.rangeText(for: try #require(result.weeks.last)) == "Nov 9–15")
    }

    @Test func rangeText_AcrossMonths_ShowsBothMonths() throws {
        let result = heatmap(now: try date(2026, 11, 10))
        let week = try #require(result.weeks.first { $0.start == (try? date(2026, 10, 26)) })
        #expect(result.rangeText(for: week) == "Oct 26 – Nov 1")
    }

    @Test func rangeText_AcrossTheYear_ShowsYears() throws {
        let result = heatmap(now: try date(2027, 3, 1))
        let week = try #require(result.weeks.first { $0.start == (try? date(2026, 12, 28)) })
        #expect(result.rangeText(for: week) == "Dec 28, 2026 – Jan 3, 2027")
    }

    @Test func rangeText_SameMonthInEarlierYear_ShowsYear() throws {
        let result = heatmap(now: try date(2026, 11, 10))
        let week = try #require(result.weeks.first)
        #expect(result.rangeText(for: week) == "Nov 17–23, 2025")
    }

    @Test func rangeText_AcrossMonthsInEarlierYear_ShowsYearOnBothEnds() throws {
        let result = heatmap(now: try date(2026, 11, 10))
        let week = try #require(result.weeks.first { $0.start == (try? date(2025, 12, 29)) })
        #expect(result.rangeText(for: week) == "Dec 29, 2025 – Jan 4, 2026")
    }

    // MARK: Gate

    @Test func isAvailable_Insights_IsProOnly() {
        #expect(!FreeTierLimits.isAvailable(.insights, isPro: false))
        #expect(FreeTierLimits.isAvailable(.insights, isPro: true))
    }

    @Test func upgradeReason_Insights_NamesInsights() {
        #expect(ProFeature.insights.upgradeReason == .insights)
        #expect(ProUpgradeReason.insights.message == "Insights are part of SoapWiz Pro.")
    }
}
