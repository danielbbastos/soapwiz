import Testing
import Foundation
@testable import SoapWiz

@Suite("Ingredient stock stamp expiry")
struct IngredientStockStampExpiryTests {

    private let calendar: Calendar
    private let now: Date

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        self.calendar = calendar
        now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12)))
    }

    private func date(byAdding component: Calendar.Component, _ value: Int) throws -> Date {
        try #require(calendar.date(byAdding: component, value: value, to: now))
    }

    private func stamp(for expiry: Date) -> IngredientStockStamp? {
        IngredientStockStamp.expiry(expiry, now: now, calendar: calendar)
    }

    @Test func expiry_InThePast_IsExpired() throws {
        #expect(stamp(for: try date(byAdding: .day, -3)) == .expired)
    }

    @Test func expiry_EarlierToday_IsExpired() throws {
        #expect(stamp(for: try date(byAdding: .hour, -1)) == .expired)
    }

    @Test func expiry_LaterToday_ExpiresInZeroDays() throws {
        #expect(stamp(for: try date(byAdding: .hour, 1)) == .expiresIn(days: 0))
    }

    @Test func expiry_WithinAMonth_ExpiresInDays() throws {
        #expect(stamp(for: try date(byAdding: .day, 10)) == .expiresIn(days: 10))
    }

    @Test func expiry_ExactlyOneMonthAway_StillStamped() throws {
        let expiry = try date(byAdding: .month, 1)
        let days = IngredientStockStamp.daysUntil(expiry, from: now, calendar: calendar)
        #expect(stamp(for: expiry) == .expiresIn(days: days))
    }

    @Test func expiry_JustPastOneMonth_HasNoStamp() throws {
        let expiry = try #require(calendar.date(byAdding: .second, value: 1, to: try date(byAdding: .month, 1)))
        #expect(stamp(for: expiry) == nil)
    }

    @Test func expiry_MonthsAway_HasNoStamp() throws {
        #expect(stamp(for: try date(byAdding: .month, 6)) == nil)
    }
}
