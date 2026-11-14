import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Which batches Home's Ready to use card lists, in what order, and how a
/// batch is marked as seen.
@Suite("Home ready", .serialized)
@MainActor
struct HomeReadyTests {

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

    /// A batch whose cure ended `daysAgo` days before today; negative is still curing.
    private func batch(
        _ name: String,
        daysAgo: Int,
        cureDays: Int = 42,
        in context: ModelContext
    ) throws -> Batch {
        let today = calendar.startOfDay(for: now)
        let made = try #require(calendar.date(byAdding: .day, value: -daysAgo - cureDays, to: today))
        let batch = Batch(recipe: nil, recipeName: name, dateCreated: made, batchCount: 1, cureDays: cureDays)
        context.insert(batch)
        return batch
    }

    private func ready(_ batches: [Batch]) -> HomeReady {
        HomeReady(batches: batches, now: now, calendar: calendar)
    }

    @Test func items_UnseenReadyToday_IsListedWithItsReadyDate() throws {
        let (container, context) = try makeContext()
        _ = container
        let today = try batch("Today", daysAgo: 0, in: context)
        let item = try #require(ready([today]).items.first)
        #expect(item.batch.recipeName == "Today")
        #expect(item.readyDate == calendar.startOfDay(for: now))
    }

    @Test func items_ReadyTwentyNineDaysAgo_IsListed() throws {
        let (container, context) = try makeContext()
        _ = container
        let old = try batch("Old", daysAgo: 29, in: context)
        #expect(ready([old]).items.map(\.batch.recipeName) == ["Old"])
    }

    @Test func items_ReadyThirtyOrMoreDaysAgo_IsLeftOut() throws {
        let (container, context) = try makeContext()
        _ = container
        let thirty = try batch("Thirty", daysAgo: 30, in: context)
        let longAgo = try batch("Long ago", daysAgo: 90, in: context)
        #expect(ready([thirty, longAgo]).items.isEmpty)
    }

    @Test func items_SeenBatch_IsLeftOut() throws {
        let (container, context) = try makeContext()
        _ = container
        let seen = try batch("Seen", daysAgo: 1, in: context)
        seen.readySeenAt = now
        let unseen = try batch("Unseen", daysAgo: 1, in: context)
        #expect(ready([seen, unseen]).items.map(\.batch.recipeName) == ["Unseen"])
    }

    @Test func items_CuringAndNoCureBatches_AreLeftOut() throws {
        let (container, context) = try makeContext()
        _ = container
        let noCure = Batch(recipe: nil, recipeName: "No cure", dateCreated: now, batchCount: 1, cureDays: 0)
        context.insert(noCure)
        let curing = try batch("Curing", daysAgo: -1, in: context)
        let done = try batch("Done", daysAgo: 1, in: context)
        #expect(ready([noCure, curing, done]).items.map(\.batch.recipeName) == ["Done"])
    }

    @Test func items_AreOrderedMostRecentlyReadyFirst() throws {
        let (container, context) = try makeContext()
        _ = container
        let result = ready([
            try batch("Two ago", daysAgo: 2, in: context),
            try batch("Today", daysAgo: 0, in: context),
            try batch("Yesterday", daysAgo: 1, in: context)
        ])
        #expect(result.items.map(\.batch.recipeName) == ["Today", "Yesterday", "Two ago"])
    }

    @Test func items_NoBatches_IsEmpty() {
        let result = ready([])
        #expect(result.items.isEmpty)
        #expect(result.count == 0)
    }

    @Test func isUnseenReady_ReadyAndUnseen_IsTrueWhateverTheAge() throws {
        let (container, context) = try makeContext()
        _ = container
        let today = try batch("Today", daysAgo: 0, in: context)
        let old = try batch("Old", daysAgo: 200, in: context)
        #expect(HomeReady.isUnseenReady(today, now: now, calendar: calendar))
        #expect(HomeReady.isUnseenReady(old, now: now, calendar: calendar))
    }

    @Test func isUnseenReady_CuringSeenOrNoCure_IsFalse() throws {
        let (container, context) = try makeContext()
        _ = container
        let curing = try batch("Curing", daysAgo: -1, in: context)
        let seen = try batch("Seen", daysAgo: 1, in: context)
        seen.readySeenAt = now
        let noCure = Batch(recipe: nil, recipeName: "No cure", dateCreated: now, batchCount: 1, cureDays: 0)
        context.insert(noCure)
        #expect(!HomeReady.isUnseenReady(curing, now: now, calendar: calendar))
        #expect(!HomeReady.isUnseenReady(seen, now: now, calendar: calendar))
        #expect(!HomeReady.isUnseenReady(noCure, now: now, calendar: calendar))
    }

    @Test func markSeen_SetsTheDateAndTheBatchLeavesTheList() throws {
        let (container, context) = try makeContext()
        _ = container
        let first = try batch("First", daysAgo: 0, in: context)
        let second = try batch("Second", daysAgo: 1, in: context)

        HomeReady.markSeen([first], now: now, context: context)

        #expect(first.readySeenAt == now)
        #expect(second.readySeenAt == nil)
        #expect(ready([first, second]).items.map(\.batch.recipeName) == ["Second"])
    }

    @Test func markSeen_PersistsAfterSaveAndRefetch() throws {
        let (container, context) = try makeContext()
        _ = container
        let first = try batch("First", daysAgo: 0, in: context)
        let second = try batch("Second", daysAgo: 1, in: context)
        try context.save()

        HomeReady.markSeen([first, second], now: now, context: context)

        let fetched = try context.fetch(FetchDescriptor<Batch>())
        #expect(fetched.count == 2)
        #expect(fetched.allSatisfy { $0.readySeenAt == now })
        #expect(ready(fetched).items.isEmpty)
    }

    @Test func markSeen_KeepsAnEarlierSeenDate() throws {
        let (container, context) = try makeContext()
        _ = container
        let earlier = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        let seen = try batch("Seen", daysAgo: 1, in: context)
        seen.readySeenAt = earlier

        HomeReady.markSeen([seen], now: now, context: context)

        #expect(seen.readySeenAt == earlier)
    }

    @Test func markSeen_SkipsABatchDeletedMeanwhile() throws {
        let (container, context) = try makeContext()
        _ = container
        let gone = try batch("Gone", daysAgo: 0, in: context)
        let kept = try batch("Kept", daysAgo: 1, in: context)
        try context.save()
        context.delete(gone)

        HomeReady.markSeen([gone, kept], now: now, context: context)

        #expect(kept.readySeenAt == now)
        #expect(try context.fetch(FetchDescriptor<Batch>()).map(\.recipeName) == ["Kept"])
    }

    @Test func visibleItems_MoreThanFour_CollapsedShowsFourAndExpandsToAll() throws {
        let (container, context) = try makeContext()
        _ = container
        let batches = try (0...5).map { try batch("B\($0)", daysAgo: $0 % 3, in: context) }
        let result = ready(batches)
        #expect(result.canExpand)
        #expect(result.visibleItems(isExpanded: false).count == 4)
        #expect(result.visibleItems(isExpanded: true).count == 6)
        #expect(result.historyCount(isExpanded: true) == 0)
    }

    @Test func visibleItems_FourOrFewer_CannotExpand() throws {
        let (container, context) = try makeContext()
        _ = container
        let result = ready(try (0..<4).map { try batch("B\($0)", daysAgo: 0, in: context) })
        #expect(!result.canExpand)
        #expect(result.visibleItems(isExpanded: true).count == 4)
    }
}
