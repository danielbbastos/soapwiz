import Testing
import Foundation
@testable import SoapWiz

@Suite("Cure notification scheduler")
struct CureNotificationSchedulerTests {

    private let calendar: Calendar

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Lisbon"))
        self.calendar = calendar
    }

    private func date(_ month: Int, _ day: Int, hour: Int = 0) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)))
    }

    private func snapshot(_ name: String, code: String = "", usable: Date? = nil, ready: Date) -> CureSnapshot {
        CureSnapshot(recipeName: name, code: code, usableDate: usable, readyDate: ready)
    }

    private func requests(_ batches: [CureSnapshot], now: Date) -> [ScheduledReminder] {
        CureNotificationScheduler.computeRequests(batches: batches, now: now, calendar: calendar)
    }

    @Test func computeRequests_NoBatches_ReturnsEmpty() throws {
        #expect(requests([], now: try date(9, 1)).isEmpty)
    }

    @Test func computeRequests_OneBatch_FiresAtNineOnTheReadyDay() throws {
        let result = requests([snapshot("Lavender", code: "LAV-260901-01", ready: try date(10, 13))], now: try date(9, 1))

        let request = try #require(result.first)
        #expect(result.count == 1)
        #expect(request.identifier == "cure-ready-20261013")
        #expect(request.fireDate == (try date(10, 13, hour: 9)))
        #expect(request.title == "Batch Ready")
        #expect(request.body == "Lavender (LAV-260901-01) has finished curing.")
    }

    @Test func computeRequests_UsableAndReady_ScheduleBothSoonestFirst() throws {
        let batch = snapshot("Castile", code: "CAS-1", usable: try date(10, 13), ready: try date(12, 1))

        let result = requests([batch], now: try date(9, 1))

        #expect(result.map(\.identifier) == ["cure-usable-20261013", "cure-ready-20261201"])
        let usable = try #require(result.first)
        #expect(usable.title == "Batch Usable")
        #expect(usable.body == "Castile (CAS-1) can be used now, and keeps improving until it's fully cured.")
    }

    /// Past the usable day but not yet ready: only the ready reminder is left.
    @Test func computeRequests_UsableDayAlreadyPast_KeepsOnlyReady() throws {
        let batch = snapshot("Castile", usable: try date(8, 20), ready: try date(12, 1))

        let result = requests([batch], now: try date(9, 1))

        #expect(result.map(\.identifier) == ["cure-ready-20261201"])
    }

    /// One batch usable and another ready on the same day are different news,
    /// so they don't share a reminder.
    @Test func computeRequests_UsableAndReadyOnTheSameDay_StaySeparate() throws {
        let day = try date(10, 13)
        let result = requests(
            [snapshot("Castile", usable: day, ready: try date(12, 1)), snapshot("Lavender", ready: day)],
            now: try date(9, 1)
        )

        #expect(Set(result.map(\.identifier)) == ["cure-usable-20261013", "cure-ready-20261013", "cure-ready-20261201"])
    }

    @Test func computeRequests_TwoBatchesSameDay_ShareOneReminder() throws {
        let ready = try date(10, 13)
        let result = requests(
            [snapshot("Oatmeal", code: "OAT-1", ready: ready), snapshot("Castile", code: "CAS-1", ready: ready)],
            now: try date(9, 1)
        )

        let request = try #require(result.first)
        #expect(result.count == 1)
        #expect(request.title == "2 Batches Ready")
        #expect(request.body == "Castile (CAS-1), Oatmeal (OAT-1) have finished curing.")
    }

    @Test func computeRequests_TwoBatchesUsableSameDay_ShareOneReminder() throws {
        let usable = try date(10, 13)
        let result = requests(
            [snapshot("Oatmeal", usable: usable, ready: try date(11, 1)), snapshot("Castile", usable: usable, ready: try date(12, 1))],
            now: try date(9, 1)
        )

        let request = try #require(result.first)
        #expect(request.title == "2 Batches Usable")
        #expect(request.body == "Castile, Oatmeal can be used now, and keep improving until they're fully cured.")
    }

    @Test func computeRequests_DifferentDays_SortedSoonestFirst() throws {
        let result = requests(
            [snapshot("Later", ready: try date(11, 20)), snapshot("Sooner", ready: try date(10, 2))],
            now: try date(9, 1)
        )

        #expect(result.map(\.identifier) == ["cure-ready-20261002", "cure-ready-20261120"])
    }

    @Test func computeRequests_ReadyDayAlreadyPast_IsSkipped() throws {
        #expect(requests([snapshot("Old", ready: try date(8, 1))], now: try date(9, 1)).isEmpty)
    }

    @Test func computeRequests_ReadyTodayBeforeNine_StillFires() throws {
        let result = requests([snapshot("Today", ready: try date(9, 1))], now: try date(9, 1, hour: 8))
        #expect(result.count == 1)
    }

    @Test func computeRequests_ReadyTodayAfterNine_IsSkipped() throws {
        #expect(requests([snapshot("Today", ready: try date(9, 1))], now: try date(9, 1, hour: 10)).isEmpty)
    }

    @Test func computeRequests_EveryIdentifier_SharesTheCancellationPrefix() throws {
        let batch = snapshot("Castile", usable: try date(10, 13), ready: try date(12, 1))
        let result = requests([batch], now: try date(9, 1))
        #expect(result.allSatisfy { $0.identifier.hasPrefix(CureNotificationScheduler.notificationPrefix) })
    }

    @Test func displayName_BatchWithoutCode_IsTheRecipeNameAlone() {
        #expect(CureNotificationScheduler.displayName(snapshot("Lavender", code: "  ", ready: .now)) == "Lavender")
    }
}
