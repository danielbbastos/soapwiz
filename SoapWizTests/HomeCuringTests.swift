import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Which batches Home's Curing card lists, in what order, and which count as
/// ready this week (SW-362).
@Suite("Home curing", .serialized)
@MainActor
struct HomeCuringTests {

    private let calendar: Calendar
    private let now: Date

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Lisbon"))
        self.calendar = calendar
        self.now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 15)))
    }

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    /// A batch whose cure ends `daysLeft` days from today.
    private func batch(
        _ name: String,
        daysLeft: Int,
        cureDays: Int = 42,
        in context: ModelContext
    ) throws -> Batch {
        let today = calendar.startOfDay(for: now)
        let made = try #require(calendar.date(byAdding: .day, value: daysLeft - cureDays, to: today))
        let batch = Batch(recipe: nil, recipeName: name, dateCreated: made, batchCount: 1, cureDays: cureDays)
        context.insert(batch)
        return batch
    }

    private func curing(_ batches: [Batch]) -> HomeCuring {
        HomeCuring(batches: batches, now: now, calendar: calendar)
    }

    @Test func items_CuringBatch_IsListed() throws {
        let (container, context) = try makeContext()
        _ = container
        let cake = try batch("Cake", daysLeft: 10, in: context)
        let result = curing([cake])
        #expect(result.items.map(\.batch.recipeName) == ["Cake"])
        #expect(result.items.first?.remaining == .days(10))
    }

    @Test func items_NoCureOrReadyBatches_AreLeftOut() throws {
        let (container, context) = try makeContext()
        _ = container
        let noCure = Batch(recipe: nil, recipeName: "No cure", dateCreated: now, batchCount: 1, cureDays: 0)
        context.insert(noCure)
        let readyToday = try batch("Ready today", daysLeft: 0, in: context)
        let readyRecently = try batch("Ready recently", daysLeft: -1, in: context)
        let longReady = try batch("Long ready", daysLeft: -20, in: context)
        let cake = try batch("Cake", daysLeft: 3, in: context)
        let result = curing([noCure, readyToday, readyRecently, longReady, cake])
        #expect(result.items.map(\.batch.recipeName) == ["Cake"])
    }

    @Test func items_AreOrderedSoonestReadyFirst() throws {
        let (container, context) = try makeContext()
        _ = container
        let far = try batch("Far", daysLeft: 60, in: context)
        let soon = try batch("Soon", daysLeft: 2, in: context)
        let middle = try batch("Middle", daysLeft: 20, in: context)
        let result = curing([far, soon, middle])
        #expect(result.items.map(\.batch.recipeName) == ["Soon", "Middle", "Far"])
    }

    @Test func isReadyThisWeek_AtTheSevenDayBoundary() throws {
        let (container, context) = try makeContext()
        _ = container
        let tomorrow = try batch("Tomorrow", daysLeft: 1, in: context)
        let seven = try batch("Seven", daysLeft: 7, in: context)
        let eight = try batch("Eight", daysLeft: 8, in: context)
        let flags = Dictionary(
            uniqueKeysWithValues: curing([tomorrow, seven, eight]).items.map { ($0.batch.recipeName, $0.isReadyThisWeek) }
        )
        #expect(flags == ["Tomorrow": true, "Seven": true, "Eight": false])
    }

    @Test func counts_ReportTotalAndReadyThisWeek() throws {
        let (container, context) = try makeContext()
        _ = container
        let result = curing([
            try batch("A", daysLeft: 3, in: context),
            try batch("B", daysLeft: 7, in: context),
            try batch("C", daysLeft: 30, in: context)
        ])
        #expect(result.count == 3)
        #expect(result.readyThisWeekCount == 2)
    }

    @Test func item_CarriesProgressAndReadyDate() throws {
        let (container, context) = try makeContext()
        _ = container
        let cake = try batch("Cake", daysLeft: 14, cureDays: 28, in: context)
        let item = try #require(curing([cake]).items.first)
        #expect(item.progress == 0.5)
        let expected = try #require(calendar.date(byAdding: .day, value: 14, to: calendar.startOfDay(for: now)))
        #expect(item.readyDate == expected)
    }

    private func manyBatches(_ count: Int, in context: ModelContext) throws -> [Batch] {
        try (1...count).map { try batch("B\($0)", daysLeft: $0, in: context) }
    }

    @Test func visibleItems_FourOrFewer_ShowsAllAndCannotExpand() throws {
        let (container, context) = try makeContext()
        _ = container
        let result = curing(try manyBatches(4, in: context))
        #expect(!result.canExpand)
        #expect(result.visibleItems(isExpanded: false).count == 4)
        #expect(result.visibleItems(isExpanded: true).count == 4)
        #expect(result.historyCount(isExpanded: true) == 0)
    }

    @Test func visibleItems_FiveToTen_CollapsedShowsFourSoonestAndExpandsToAll() throws {
        let (container, context) = try makeContext()
        _ = container
        let result = curing(Array(try manyBatches(7, in: context).reversed()))
        #expect(result.canExpand)
        #expect(result.visibleItems(isExpanded: false).map(\.batch.recipeName) == ["B1", "B2", "B3", "B4"])
        #expect(result.visibleItems(isExpanded: true).count == 7)
        #expect(result.historyCount(isExpanded: true) == 0)
    }

    @Test func visibleItems_ExactlyTen_ExpandsToAllWithNoOverflow() throws {
        let (container, context) = try makeContext()
        _ = container
        let result = curing(try manyBatches(10, in: context))
        #expect(result.visibleItems(isExpanded: true).count == 10)
        #expect(result.historyCount(isExpanded: true) == 0)
    }

    @Test func visibleItems_MoreThanTen_CapsExpandedAtTenAndCountsTheRest() throws {
        let (container, context) = try makeContext()
        _ = container
        let result = curing(try manyBatches(13, in: context))
        let expanded = result.visibleItems(isExpanded: true)
        #expect(expanded.count == 10)
        #expect(expanded.last?.batch.recipeName == "B10")
        #expect(result.historyCount(isExpanded: true) == 3)
        #expect(result.visibleItems(isExpanded: false).count == 4)
        #expect(result.historyCount(isExpanded: false) == 0)
    }

    @Test func items_NoBatches_IsEmpty() {
        let result = curing([])
        #expect(result.items.isEmpty)
        #expect(result.count == 0)
        #expect(result.readyThisWeekCount == 0)
    }
}
