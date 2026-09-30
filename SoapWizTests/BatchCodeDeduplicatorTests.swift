import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Settling a generated code two devices both handed out while out of touch
/// (SW-175): the batch made first keeps it, later ones move along.
@Suite("Batch code deduplicator", .serialized)
@MainActor
struct BatchCodeDeduplicatorTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    private func date(hour: Int, minute: Int = 0) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        return try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: hour, minute: minute))
        )
    }

    @discardableResult
    private func insertBatch(
        _ ctx: ModelContext, code: String, recipeName: String = "Lavender", hour: Int, minute: Int = 0
    ) throws -> Batch {
        let batch = Batch.mock(code: code, recipeName: recipeName, dateCreated: try date(hour: hour, minute: minute))
        ctx.insert(batch)
        return batch
    }

    @Test func resolve_EmptyStore_RenumbersNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container

        #expect(try BatchCodeDeduplicator.resolve(in: ctx) == 0)
    }

    @Test func resolve_DistinctCodes_AreLeftAlone() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let first = try insertBatch(ctx, code: "LAV-260930-01", hour: 9)
        let second = try insertBatch(ctx, code: "LAV-260930-02", hour: 10)
        try ctx.save()

        let renumbered = try BatchCodeDeduplicator.resolve(in: ctx)

        #expect(renumbered == 0)
        #expect(first.code == "LAV-260930-01")
        #expect(second.code == "LAV-260930-02")
    }

    /// Inserted later-first, so the winner can only be the older batch if the
    /// pass goes by date rather than by the order it found them in.
    @Test func resolve_TwoBatchesShareGeneratedCode_EarlierKeepsIt() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let later = try insertBatch(ctx, code: "LAV-260930-01", hour: 15)
        let earlier = try insertBatch(ctx, code: "LAV-260930-01", hour: 9)
        try ctx.save()

        let renumbered = try BatchCodeDeduplicator.resolve(in: ctx)

        #expect(renumbered == 1)
        #expect(earlier.code == "LAV-260930-01")
        #expect(later.code == "LAV-260930-02")
    }

    @Test func resolve_ThreeBatchesShareCode_LaterOnesTakeSuccessiveSequences() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let third = try insertBatch(ctx, code: "LAV-260930-01", hour: 18)
        let first = try insertBatch(ctx, code: "LAV-260930-01", hour: 9)
        let second = try insertBatch(ctx, code: "LAV-260930-01", hour: 12)
        try ctx.save()

        let renumbered = try BatchCodeDeduplicator.resolve(in: ctx)

        #expect(renumbered == 2)
        #expect(first.code == "LAV-260930-01")
        #expect(second.code == "LAV-260930-02")
        #expect(third.code == "LAV-260930-03")
    }

    /// The loser must not be moved onto a code some other batch already holds.
    @Test func resolve_NextSequenceAlreadyInUse_SkipsPastIt() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try insertBatch(ctx, code: "LAV-260930-01", hour: 9)
        let clashing = try insertBatch(ctx, code: "LAV-260930-01", hour: 10)
        let alreadySecond = try insertBatch(ctx, code: "LAV-260930-02", hour: 11)
        try ctx.save()

        try BatchCodeDeduplicator.resolve(in: ctx)

        #expect(alreadySecond.code == "LAV-260930-02")
        #expect(clashing.code == "LAV-260930-03")
    }

    @Test func resolve_CodesDifferingOnlyInCase_AreTheSameCode() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let earlier = try insertBatch(ctx, code: "lav-260930-01", hour: 9)
        let later = try insertBatch(ctx, code: "LAV-260930-01 ", hour: 10)
        try ctx.save()

        let renumbered = try BatchCodeDeduplicator.resolve(in: ctx)

        #expect(renumbered == 1)
        #expect(earlier.code == "lav-260930-01")
        #expect(later.code == "LAV-260930-02")
    }

    /// A code the user typed is theirs to keep, clash or not.
    @Test func resolve_HandTypedDuplicates_AreLeftAlone() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let first = try insertBatch(ctx, code: "2026/14", hour: 9)
        let second = try insertBatch(ctx, code: "2026/14", hour: 10)
        try ctx.save()

        let renumbered = try BatchCodeDeduplicator.resolve(in: ctx)

        #expect(renumbered == 0)
        #expect(first.code == "2026/14")
        #expect(second.code == "2026/14")
    }

    @Test func resolve_BatchesWithoutCode_AreNotTreatedAsDuplicates() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let first = try insertBatch(ctx, code: "", hour: 9)
        let second = try insertBatch(ctx, code: "", hour: 10)
        try ctx.save()

        let renumbered = try BatchCodeDeduplicator.resolve(in: ctx)

        #expect(renumbered == 0)
        #expect(first.code.isEmpty)
        #expect(second.code.isEmpty)
    }

    /// Two batches that synced data can't tell apart: a device guessing which
    /// to move could guess differently from its peer, so neither moves.
    @Test func resolve_IndistinguishableBatches_AreLeftSharingTheCode() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let one = try insertBatch(ctx, code: "LAV-260930-01", hour: 9)
        let other = try insertBatch(ctx, code: "LAV-260930-01", hour: 9)
        try ctx.save()

        let renumbered = try BatchCodeDeduplicator.resolve(in: ctx)

        #expect(renumbered == 0)
        #expect(one.code == "LAV-260930-01")
        #expect(other.code == "LAV-260930-01")
    }

    @Test func resolve_SeparateClashes_AreSettledIndependently() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try insertBatch(ctx, code: "LAV-260930-01", hour: 9)
        let laterLavender = try insertBatch(ctx, code: "LAV-260930-01", hour: 10)
        try insertBatch(ctx, code: "ROS-260930-01", recipeName: "Rose", hour: 9)
        let laterRose = try insertBatch(ctx, code: "ROS-260930-01", recipeName: "Rose", hour: 10)
        try ctx.save()

        let renumbered = try BatchCodeDeduplicator.resolve(in: ctx)

        #expect(renumbered == 2)
        #expect(laterLavender.code == "LAV-260930-02")
        #expect(laterRose.code == "ROS-260930-02")
    }

    @Test func resolve_SecondPass_WritesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try insertBatch(ctx, code: "LAV-260930-01", hour: 9)
        let later = try insertBatch(ctx, code: "LAV-260930-01", hour: 10)
        try ctx.save()
        try BatchCodeDeduplicator.resolve(in: ctx)

        let renumbered = try BatchCodeDeduplicator.resolve(in: ctx)

        #expect(renumbered == 0)
        #expect(later.code == "LAV-260930-02")
        #expect(ctx.hasChanges == false)
    }

    /// What two devices that each made the day's first batch end up with once
    /// both have synced and run the pass: the same codes on the same batches.
    @Test func resolve_TwoStoresWithTheSameBatches_ReachTheSameCodes() throws {
        let (containerA, deviceA) = try makeContext()
        let (containerB, deviceB) = try makeContext()
        _ = (containerA, containerB)
        // Each device holds its own batch first and the other's second.
        try insertBatch(deviceA, code: "LAV-260930-01", hour: 9, minute: 5)
        try insertBatch(deviceA, code: "LAV-260930-01", hour: 9, minute: 40)
        try insertBatch(deviceB, code: "LAV-260930-01", hour: 9, minute: 40)
        try insertBatch(deviceB, code: "LAV-260930-01", hour: 9, minute: 5)
        try deviceA.save()
        try deviceB.save()

        try BatchCodeDeduplicator.resolve(in: deviceA)
        try BatchCodeDeduplicator.resolve(in: deviceB)

        #expect(try codesByDate(in: deviceA) == ["LAV-260930-01", "LAV-260930-02"])
        #expect(try codesByDate(in: deviceB) == ["LAV-260930-01", "LAV-260930-02"])
    }

    private func codesByDate(in ctx: ModelContext) throws -> [String] {
        try ctx.fetch(FetchDescriptor<Batch>())
            .sorted { $0.dateCreated < $1.dateCreated }
            .map(\.code)
    }
}
