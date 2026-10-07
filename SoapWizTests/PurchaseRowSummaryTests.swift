import Testing
import Foundation
@testable import SoapWiz

@Suite("Purchase row summary")
struct PurchaseRowSummaryTests {

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

    private func summary(expiry: Date?, remaining: Double = 100, badge: String = "") -> PurchaseRowSummary {
        PurchaseRowSummary(
            expiryDate: expiry,
            remainingAmount: remaining,
            badge: badge,
            now: now,
            calendar: calendar
        )
    }

    @Test func noExpiry_WithStock_HasNoStatusAndNoStamps() {
        let result = summary(expiry: nil)
        #expect(result.status == .none)
        #expect(result.stamps.isEmpty)
    }

    @Test func futureExpiry_BeyondAMonth_ShowsExpiresStatusWithoutStamp() throws {
        let expiry = try date(byAdding: .month, 6)
        let result = summary(expiry: expiry)
        #expect(result.status == .expires(expiry))
        #expect(result.stamps.isEmpty)
    }

    @Test func expiryWithinAMonth_AddsExpiresInStamp() throws {
        let expiry = try date(byAdding: .day, 10)
        let result = summary(expiry: expiry)
        #expect(result.status == .expires(expiry))
        #expect(result.stamps == [.stock(.expiresIn(days: 10))])
    }

    @Test func expiryExactlyAtOneMonth_StillStamps() throws {
        let expiry = try date(byAdding: .month, 1)
        let result = summary(expiry: expiry)
        #expect(result.stamps.count == 1)
    }

    @Test func expiryJustPastAMonth_DoesNotStamp() throws {
        let expiry = try date(byAdding: .day, 32)
        #expect(summary(expiry: expiry).stamps.isEmpty)
    }

    @Test func expiredWithStock_ShowsExpiredStatusAndStamp() throws {
        let result = summary(expiry: try date(byAdding: .day, -3))
        #expect(result.status == .expired)
        #expect(result.stamps == [.stock(.expired)])
    }

    @Test func usedUp_WithoutExpiry_ShowsUsedUp() {
        let result = summary(expiry: nil, remaining: 0)
        #expect(result.status == .usedUp)
        #expect(result.stamps.isEmpty)
    }

    @Test func usedUp_WithPastExpiry_WinsOverExpiredAndDropsStamp() throws {
        let result = summary(expiry: try date(byAdding: .day, -3), remaining: 0)
        #expect(result.status == .usedUp)
        #expect(result.stamps.isEmpty)
    }

    @Test func usedUp_WithSoonExpiry_WinsOverExpiry() throws {
        let result = summary(expiry: try date(byAdding: .day, 5), remaining: 0)
        #expect(result.status == .usedUp)
        #expect(result.stamps.isEmpty)
    }

    @Test func badge_BecomesNeutralStamp() throws {
        let result = summary(expiry: nil, badge: "Lot A")
        #expect(result.stamps == [.badge("Lot A")])
        let stamp = try #require(result.stamps.first)
        #expect(stamp.word == "Lot A")
        #expect(stamp.tone == .neutral)
        #expect(stamp.glyph == nil)
    }

    @Test func badge_OnUsedUpPurchase_StillShows() {
        let result = summary(expiry: nil, remaining: 0, badge: "Lot A")
        #expect(result.stamps == [.badge("Lot A")])
    }

    @Test func expiryStampComesBeforeBadge() throws {
        let result = summary(expiry: try date(byAdding: .day, -1), badge: "Lot A")
        #expect(result.stamps == [.stock(.expired), .badge("Lot A")])
    }

    @Test func stamps_NeverExceedTwo() throws {
        let soon = summary(expiry: try date(byAdding: .day, 4), badge: "Lot A")
        let expired = summary(expiry: try date(byAdding: .day, -4), badge: "Lot A")
        #expect(soon.stamps.count == 2)
        #expect(expired.stamps.count == 2)
        #expect(soon.stamps.first == .stock(.expiresIn(days: 4)))
    }
}
