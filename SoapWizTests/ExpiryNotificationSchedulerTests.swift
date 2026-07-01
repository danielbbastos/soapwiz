import Testing
import Foundation
@testable import SoapWiz

@Suite
struct ExpiryNotificationSchedulerTests {
    private let calendar = Calendar.current

    private func makeSnapshot(
        name: String = "Olive Oil",
        expiryDate: Date,
        remainingAmount: Double = 500
    ) -> PurchaseSnapshot {
        PurchaseSnapshot(
            ingredientName: name,
            expiryDate: expiryDate,
            remainingAmount: remainingAmount
        )
    }

    // MARK: - Filtering

    @Test func computeRequests_NoPurchases_ReturnsEmpty() {
        let requests = ExpiryNotificationScheduler.computeRequests(
            purchases: [],
            now: .now,
            calendar: calendar
        )
        #expect(requests.isEmpty)
    }

    @Test func computeRequests_ExpiredPurchase_ReturnsEmpty() {
        let now = Date.now
        let pastExpiry = calendar.date(byAdding: .day, value: -1, to: now)!
        let snapshot = makeSnapshot(expiryDate: pastExpiry)

        let requests = ExpiryNotificationScheduler.computeRequests(
            purchases: [snapshot],
            now: now,
            calendar: calendar
        )
        #expect(requests.isEmpty)
    }

    @Test func computeRequests_FullyConsumedPurchase_ReturnsEmpty() {
        let now = Date.now
        let futureExpiry = calendar.date(byAdding: .month, value: 3, to: now)!
        let snapshot = makeSnapshot(expiryDate: futureExpiry, remainingAmount: 0)

        let requests = ExpiryNotificationScheduler.computeRequests(
            purchases: [snapshot],
            now: now,
            calendar: calendar
        )
        #expect(requests.isEmpty)
    }

    // MARK: - Threshold scheduling

    @Test func computeRequests_ExpiryMoreThanOneMonthAway_SchedulesBothThresholds() {
        let now = Date.now
        let expiryDate = calendar.date(byAdding: .month, value: 3, to: now)!
        let snapshot = makeSnapshot(expiryDate: expiryDate)

        let requests = ExpiryNotificationScheduler.computeRequests(
            purchases: [snapshot],
            now: now,
            calendar: calendar
        )

        #expect(requests.count == 2)
        let identifiers = requests.map(\.identifier)
        #expect(identifiers.contains { $0.contains("1month") })
        #expect(identifiers.contains { $0.contains("1week") })
    }

    @Test func computeRequests_ExpiryLessThanOneMonthButMoreThanOneWeek_SchedulesOnlyOneWeek() {
        let now = Date.now
        let expiryDate = calendar.date(byAdding: .day, value: 20, to: now)!
        let snapshot = makeSnapshot(expiryDate: expiryDate)

        let requests = ExpiryNotificationScheduler.computeRequests(
            purchases: [snapshot],
            now: now,
            calendar: calendar
        )

        #expect(requests.count == 1)
        #expect(requests[0].identifier.contains("1week"))
    }

    @Test func computeRequests_ExpiryLessThanOneWeekAway_ReturnsEmpty() {
        let now = Date.now
        let expiryDate = calendar.date(byAdding: .day, value: 3, to: now)!
        let snapshot = makeSnapshot(expiryDate: expiryDate)

        let requests = ExpiryNotificationScheduler.computeRequests(
            purchases: [snapshot],
            now: now,
            calendar: calendar
        )

        #expect(requests.isEmpty)
    }

    // MARK: - Calendar-based date computation

    @Test func computeRequests_ThresholdDatesComputedViaCalendar() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 10))!
        let expiryDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 30))!
        let snapshot = makeSnapshot(expiryDate: expiryDate)

        let requests = ExpiryNotificationScheduler.computeRequests(
            purchases: [snapshot],
            now: now,
            calendar: calendar
        )

        let oneMonthRequest = try? #require(requests.first { $0.identifier.contains("1month") })
        let oneWeekRequest = try? #require(requests.first { $0.identifier.contains("1week") })

        let expectedOneMonth = calendar.date(from: DateComponents(
            year: 2026, month: 5, day: 30, hour: 9, minute: 0
        ))!
        let expectedOneWeek = calendar.date(from: DateComponents(
            year: 2026, month: 6, day: 23, hour: 9, minute: 0
        ))!

        #expect(oneMonthRequest?.fireDate == expectedOneMonth)
        #expect(oneWeekRequest?.fireDate == expectedOneWeek)
    }

    // MARK: - Grouping

    @Test func computeRequests_MultiplePurchasesSameExpiryDay_GroupedIntoOneNotification() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let expiryDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!

        let snapshots = [
            makeSnapshot(name: "Olive Oil", expiryDate: expiryDate),
            makeSnapshot(name: "Coconut Oil", expiryDate: expiryDate),
            makeSnapshot(name: "Palm Oil", expiryDate: expiryDate)
        ]

        let requests = ExpiryNotificationScheduler.computeRequests(
            purchases: snapshots,
            now: now,
            calendar: calendar
        )

        let oneMonthRequests = requests.filter { $0.identifier.contains("1month") }
        #expect(oneMonthRequests.count == 1)
        #expect(oneMonthRequests[0].title == "3 Ingredients Expiring Soon")
        #expect(oneMonthRequests[0].body.contains("Coconut Oil"))
        #expect(oneMonthRequests[0].body.contains("Olive Oil"))
        #expect(oneMonthRequests[0].body.contains("Palm Oil"))
    }

    @Test func computeRequests_PurchasesDifferentExpiryDays_SeparateNotifications() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let expiry1 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let expiry2 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20))!

        let snapshots = [
            makeSnapshot(name: "Olive Oil", expiryDate: expiry1),
            makeSnapshot(name: "Coconut Oil", expiryDate: expiry2)
        ]

        let requests = ExpiryNotificationScheduler.computeRequests(
            purchases: snapshots,
            now: now,
            calendar: calendar
        )

        let oneMonthRequests = requests.filter { $0.identifier.contains("1month") }
        #expect(oneMonthRequests.count == 2)
    }

    // MARK: - Notification content

    @Test func computeRequests_SingleIngredient_SingularContent() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let expiryDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let snapshot = makeSnapshot(name: "Olive Oil", expiryDate: expiryDate)

        let requests = ExpiryNotificationScheduler.computeRequests(
            purchases: [snapshot],
            now: now,
            calendar: calendar
        )

        let monthRequest = requests.first { $0.identifier.contains("1month") }
        #expect(monthRequest?.title == "Ingredient Expiring Soon")
        #expect(monthRequest?.body == "Olive Oil expires within a month.")

        let weekRequest = requests.first { $0.identifier.contains("1week") }
        #expect(weekRequest?.title == "Ingredient Expiring Soon")
        #expect(weekRequest?.body == "Olive Oil expires within a week.")
    }

    // MARK: - Stable identifiers

    @Test func computeRequests_SameInput_ProducesSameIdentifiers() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let expiryDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let snapshot = makeSnapshot(expiryDate: expiryDate)

        let first = ExpiryNotificationScheduler.computeRequests(
            purchases: [snapshot], now: now, calendar: calendar
        )
        let second = ExpiryNotificationScheduler.computeRequests(
            purchases: [snapshot], now: now, calendar: calendar
        )

        #expect(first == second)
    }

    // MARK: - Sorted output

    @Test func computeRequests_ResultsSortedByFireDate() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let expiry1 = calendar.date(from: DateComponents(year: 2026, month: 4, day: 10))!
        let expiry2 = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!

        let snapshots = [
            makeSnapshot(name: "Late", expiryDate: expiry2),
            makeSnapshot(name: "Early", expiryDate: expiry1)
        ]

        let requests = ExpiryNotificationScheduler.computeRequests(
            purchases: snapshots, now: now, calendar: calendar
        )

        let fireDates = requests.map(\.fireDate)
        #expect(fireDates == fireDates.sorted())
    }

    // MARK: - Mixed scenarios

    @Test func computeRequests_MixedEligibility_OnlySchedulesEligible() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!

        let snapshots = [
            makeSnapshot(name: "Expired", expiryDate: calendar.date(
                byAdding: .day, value: -10, to: now)!),
            makeSnapshot(name: "Consumed", expiryDate: calendar.date(
                byAdding: .month, value: 2, to: now)!, remainingAmount: 0),
            makeSnapshot(name: "TooSoon", expiryDate: calendar.date(
                byAdding: .day, value: 3, to: now)!),
            makeSnapshot(name: "Valid", expiryDate: calendar.date(
                byAdding: .month, value: 2, to: now)!)
        ]

        let requests = ExpiryNotificationScheduler.computeRequests(
            purchases: snapshots, now: now, calendar: calendar
        )

        let allBodies = requests.map(\.body).joined()
        #expect(!allBodies.contains("Expired"))
        #expect(!allBodies.contains("Consumed"))
        #expect(!allBodies.contains("TooSoon"))
        #expect(allBodies.contains("Valid"))
    }
}
