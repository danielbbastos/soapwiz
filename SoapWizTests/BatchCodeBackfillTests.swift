import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The pass that codes batches made before batches had a code (SW-175), or
/// that arrive without one from a backup or an older build.
@Suite("Batch code backfill", .serialized)
@MainActor
struct BatchCodeBackfillTests {

    private let utc: TimeZone

    init() throws {
        utc = try #require(TimeZone(identifier: "UTC"))
    }

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    private func date(_ day: Int, hour: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour)))
    }

    @discardableResult
    private func insertBatch(
        _ ctx: ModelContext, recipeName: String = "Lavender", code: String = "", day: Int = 30, hour: Int
    ) throws -> Batch {
        let batch = Batch.mock(code: code, recipeName: recipeName, dateCreated: try date(day, hour: hour))
        ctx.insert(batch)
        return batch
    }

    @Test func fill_EmptyStore_FillsNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container

        #expect(try BatchCodeBackfill.fillMissingCodes(in: ctx, timeZone: utc) == 0)
    }

    @Test func fill_BatchWithoutCode_TakesCodeFromItsRecipeAndDate() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let batch = try insertBatch(ctx, hour: 9)
        try ctx.save()

        let filled = try BatchCodeBackfill.fillMissingCodes(in: ctx, timeZone: utc)

        #expect(filled == 1)
        #expect(batch.code == "LAV-260930-01")
    }

    /// Inserted newest first, so the sequence can only come out right if the
    /// pass orders the batches itself.
    @Test func fill_SameRecipeSameDay_NumbersOldestFirst() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let evening = try insertBatch(ctx, hour: 20)
        let morning = try insertBatch(ctx, hour: 8)
        let noon = try insertBatch(ctx, hour: 12)
        try ctx.save()

        let filled = try BatchCodeBackfill.fillMissingCodes(in: ctx, timeZone: utc)

        #expect(filled == 3)
        #expect(morning.code == "LAV-260930-01")
        #expect(noon.code == "LAV-260930-02")
        #expect(evening.code == "LAV-260930-03")
    }

    @Test func fill_DifferentRecipesAndDays_EachStartTheirOwnSequence() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let lavender = try insertBatch(ctx, hour: 9)
        let rose = try insertBatch(ctx, recipeName: "Rose", hour: 10)
        let earlierLavender = try insertBatch(ctx, day: 29, hour: 9)
        try ctx.save()

        try BatchCodeBackfill.fillMissingCodes(in: ctx, timeZone: utc)

        #expect(lavender.code == "LAV-260930-01")
        #expect(rose.code == "ROS-260930-01")
        #expect(earlierLavender.code == "LAV-260929-01")
    }

    @Test func fill_ExistingCode_IsLeftAlone() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let custom = try insertBatch(ctx, code: "2026/14", hour: 9)
        try ctx.save()

        let filled = try BatchCodeBackfill.fillMissingCodes(in: ctx, timeZone: utc)

        #expect(filled == 0)
        #expect(custom.code == "2026/14")
    }

    @Test func fill_SequenceAlreadyStarted_ContinuesPastIt() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try insertBatch(ctx, code: "LAV-260930-01", hour: 9)
        let uncoded = try insertBatch(ctx, hour: 8)
        try ctx.save()

        try BatchCodeBackfill.fillMissingCodes(in: ctx, timeZone: utc)

        #expect(uncoded.code == "LAV-260930-02")
    }

    @Test func fill_WhitespaceOnlyCode_CountsAsMissing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let blank = try insertBatch(ctx, code: "   ", hour: 9)
        try ctx.save()

        try BatchCodeBackfill.fillMissingCodes(in: ctx, timeZone: utc)

        #expect(blank.code == "LAV-260930-01")
    }

    @Test func fill_RecipeNameWithNothingToAbbreviate_UsesFallbackPrefix() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let unnamed = try insertBatch(ctx, recipeName: "", hour: 9)
        try ctx.save()

        try BatchCodeBackfill.fillMissingCodes(in: ctx, timeZone: utc)

        #expect(unnamed.code == "\(BatchCodeGenerator.fallbackPrefix)-260930-01")
    }

    @Test func fill_SecondPass_WritesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let batch = try insertBatch(ctx, hour: 9)
        try ctx.save()
        try BatchCodeBackfill.fillMissingCodes(in: ctx, timeZone: utc)
        let firstCode = batch.code

        let filled = try BatchCodeBackfill.fillMissingCodes(in: ctx, timeZone: utc)

        #expect(filled == 0)
        #expect(batch.code == firstCode)
        #expect(ctx.hasChanges == false)
    }

    @Test func fill_PersistsTheCodes() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try insertBatch(ctx, hour: 9)
        try ctx.save()

        try BatchCodeBackfill.fillMissingCodes(in: ctx, timeZone: utc)

        #expect(ctx.hasChanges == false)
        let fetched = try #require(try ctx.fetch(FetchDescriptor<Batch>()).first)
        #expect(fetched.code == "LAV-260930-01")
    }
}

extension Batch {
    static func mock(
        code: String = "",
        recipeName: String = "Lavender",
        dateCreated: Date = .now,
        batchCount: Int = 1,
        totalCost: Double = 0
    ) -> Batch {
        Batch(
            recipe: nil,
            code: code,
            recipeName: recipeName,
            dateCreated: dateCreated,
            batchCount: batchCount,
            totalCost: totalCost
        )
    }
}
