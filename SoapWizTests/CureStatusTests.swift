import Testing
import Foundation
@testable import SoapWiz

@Suite("Cure status")
struct CureStatusTests {

    private let calendar: Calendar

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Lisbon"))
        self.calendar = calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private func status(made: Date, cureDays: Int, now: Date) -> CureStatus {
        CureStatus(dateCreated: made, cureDays: cureDays, now: now, calendar: calendar)
    }

    @Test(arguments: [0, -7])
    func status_NoCure_IsNone(_ cureDays: Int) throws {
        let made = try date(2026, 9, 1)
        #expect(status(made: made, cureDays: cureDays, now: made) == .none)
        #expect(CureStatus.readyDate(dateCreated: made, cureDays: cureDays, calendar: calendar) == nil)
    }

    @Test func readyDate_IsStartOfTheDayTheCureEnds() throws {
        let made = try date(2026, 9, 1, hour: 22)
        let ready = CureStatus.readyDate(dateCreated: made, cureDays: 7, calendar: calendar)
        #expect(ready == (try date(2026, 9, 8, hour: 0)))
    }

    /// Lisbon leaves summer time on 25 October 2026, so that day is 25 hours
    /// long; counting in calendar days keeps the ready day on the 29th.
    @Test func readyDate_AcrossDaylightSavingChange_StaysOnTheCalendarDay() throws {
        let made = try date(2026, 10, 1)
        let ready = CureStatus.readyDate(dateCreated: made, cureDays: 28, calendar: calendar)
        #expect(ready == (try date(2026, 10, 29, hour: 0)))
    }

    @Test func status_DayMade_IsCuringWithNoProgress() throws {
        let made = try date(2026, 9, 1, hour: 9)
        #expect(status(made: made, cureDays: 42, now: try date(2026, 9, 1, hour: 23)) == .curing(remaining: .days(42), progress: 0))
    }

    @Test func status_HalfwayThrough_ReportsDaysLeftAndProgress() throws {
        let made = try date(2026, 9, 1)
        #expect(status(made: made, cureDays: 28, now: try date(2026, 9, 15)) == .curing(remaining: .days(14), progress: 0.5))
    }

    @Test func status_DayBeforeReady_HasOneDayLeft() throws {
        let made = try date(2026, 9, 1)
        #expect(status(made: made, cureDays: 7, now: try date(2026, 9, 7, hour: 23)) == .curing(remaining: .days(1), progress: 6.0 / 7.0))
    }

    @Test func status_OnTheReadyDay_IsReady() throws {
        let made = try date(2026, 9, 1, hour: 23)
        #expect(status(made: made, cureDays: 7, now: try date(2026, 9, 8, hour: 0)) == .ready)
    }

    @Test func status_LongAfterReady_IsReady() throws {
        let made = try date(2026, 1, 1)
        #expect(status(made: made, cureDays: 42, now: try date(2026, 9, 1)) == .ready)
    }

    /// A batch dated ahead of the clock — another device's clock, say — reads
    /// as just started rather than with negative progress.
    @Test func status_MadeInTheFuture_ClampsProgressToZero() throws {
        let made = try date(2026, 9, 10)
        #expect(status(made: made, cureDays: 7, now: try date(2026, 9, 1)) == .curing(remaining: .days(16), progress: 0))
    }

    // MARK: - Usable from

    @Test func usableDate_CastileGivenSixMonths_IsSixWeeksIn() throws {
        let made = try date(2026, 9, 1, hour: 18)
        let usable = CureStatus.usableDate(dateCreated: made, cureDays: 182, band: .castile, calendar: calendar)
        #expect(usable == (try date(2026, 10, 13, hour: 0)))
    }

    @Test func usableDate_NoBand_IsNil() throws {
        let made = try date(2026, 9, 1)
        #expect(CureStatus.usableDate(dateCreated: made, cureDays: 42, band: nil, calendar: calendar) == nil)
    }

    /// A cure set to the band's shortest, or shorter, has no earlier usable
    /// day: the ready date is all there is.
    @Test(arguments: [28, 21])
    func usableDate_CureNoLongerThanTheShortest_IsNil(_ cureDays: Int) throws {
        let made = try date(2026, 9, 1)
        #expect(CureStatus.usableDate(dateCreated: made, cureDays: cureDays, band: .typicalCold, calendar: calendar) == nil)
    }

    // MARK: - Days or weeks

    /// 1 September to 1 November is exactly two months: still counted in days.
    @Test func remaining_ReadyExactlyTwoMonthsOut_IsInDays() throws {
        let made = try date(2026, 9, 1)
        #expect(status(made: made, cureDays: 61, now: made) == .curing(remaining: .days(61), progress: 0))
    }

    /// One day past two months, 62 days is 8 weeks and 6 days: rounded up to 9.
    @Test func remaining_ReadyJustOverTwoMonthsOut_IsInWeeksRoundedUp() throws {
        let made = try date(2026, 9, 1)
        #expect(status(made: made, cureDays: 62, now: made) == .curing(remaining: .weeks(9), progress: 0))
    }

    @Test func remaining_CastileOnTheDayMade_IsTwentySixWeeks() throws {
        let made = try date(2026, 9, 1)
        #expect(status(made: made, cureDays: 182, now: made) == .curing(remaining: .weeks(26), progress: 0))
    }

    /// The unit follows what's left, not the cure's length: a long cure near
    /// its end counts down in days.
    @Test func remaining_LongCureNearItsEnd_SwitchesToDays() throws {
        let made = try date(2026, 1, 1)
        let now = try date(2026, 6, 1)
        let status = status(made: made, cureDays: 182, now: now)
        guard case .curing(let remaining, _) = status else {
            Issue.record("Expected curing, got \(status)")
            return
        }
        #expect(remaining == .days(31))
    }
}
