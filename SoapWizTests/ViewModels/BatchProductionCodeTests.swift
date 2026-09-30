import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The code a batch leaves creation with (SW-175): suggested from the recipe
/// and the day, the user's to change, and never missing.
@Suite("BatchProductionViewModel – batch code", .serialized)
@MainActor
struct BatchProductionCodeTests: BatchProductionTestHelpers {

    /// An untracked model over a one-oil recipe: creation always succeeds, so
    /// each test is about the code alone.
    private func makeModel(_ ctx: ModelContext, recipeName: String = "Lavender") -> BatchProductionViewModel {
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)
        recipe.name = recipeName
        return BatchProductionViewModel(recipe: recipe, lyeCandidates: [], tracksInventory: false)
    }

    private func expectedCode(
        _ recipeName: String = "Lavender", on date: Date, existingCodes: [String] = []
    ) -> String {
        BatchCodeGenerator.suggestedCode(recipeName: recipeName, date: date, existingCodes: existingCodes)
    }

    // MARK: - Suggesting

    @Test func suggestCode_FreshModel_FillsCodeWithSuggestion() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModel(ctx)
        let now = Date.now

        model.suggestCode(existingCodes: [], date: now)

        #expect(model.code == expectedCode(on: now))
        #expect(model.suggestedCode == model.code)
    }

    @Test func suggestCode_CodesAlreadyInUse_SuggestsTheNextOne() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModel(ctx)
        let now = Date.now
        let taken = expectedCode(on: now)

        model.suggestCode(existingCodes: [taken], date: now)

        #expect(model.code == expectedCode(on: now, existingCodes: [taken]))
        #expect(model.code != taken)
    }

    /// A code that syncs in while the sheet is open moves the suggestion on,
    /// as long as the user hasn't typed over it.
    @Test func suggestCode_CalledAgainWithUntouchedCode_FollowsNewSuggestion() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModel(ctx)
        let now = Date.now
        model.suggestCode(existingCodes: [], date: now)
        let first = model.code

        model.suggestCode(existingCodes: [first], date: now)

        #expect(model.code != first)
        #expect(model.code == model.suggestedCode)
    }

    @Test func suggestCode_CalledAgainAfterUserTypedCode_KeepsTheirCode() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModel(ctx)
        let now = Date.now
        model.suggestCode(existingCodes: [], date: now)
        let first = model.code
        model.code = "2026/14"

        model.suggestCode(existingCodes: [first], date: now)

        #expect(model.code == "2026/14")
        #expect(model.suggestedCode == expectedCode(on: now, existingCodes: [first]))
    }

    // MARK: - Duplicate warning

    @Test func codeIsTaken_AnotherBatchHasTheCode_ReturnsTrue() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModel(ctx)
        let existing = Batch.mock(code: "2026/14")
        ctx.insert(existing)

        model.code = "2026/14"

        #expect(model.codeIsTaken(among: [existing]))
    }

    @Test func codeIsTaken_FreshSuggestion_ReturnsFalse() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModel(ctx)
        let now = Date.now
        let existing = Batch.mock(code: expectedCode(on: now))
        ctx.insert(existing)

        model.suggestCode(existingCodes: [existing.code], date: now)

        #expect(model.codeIsTaken(among: [existing]) == false)
    }

    // MARK: - Creating

    @Test func create_StampsTheSuggestedCode() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModel(ctx)
        let now = Date.now
        model.suggestCode(existingCodes: [], date: now)

        let batch = try #require(model.create(context: ctx, date: now))

        #expect(batch.code == expectedCode(on: now))
        #expect(batch.dateCreated == now)
    }

    @Test func create_UserTypedCode_IsStampedTrimmed() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModel(ctx)
        model.suggestCode(existingCodes: [])
        model.code = "  2026/14 "

        let batch = try #require(model.create(context: ctx))

        #expect(batch.code == "2026/14")
    }

    @Test func create_DuplicateCode_CreatesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModel(ctx)
        ctx.insert(Batch.mock(code: "2026/14"))
        model.code = "2026/14"

        #expect(model.create(context: ctx) == nil)
        #expect(try ctx.fetch(FetchDescriptor<Batch>()).count == 1)
    }

    @Test func create_DuplicateCodeInAnotherCaseWithSpaces_CreatesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModel(ctx)
        ctx.insert(Batch.mock(code: "LAV-260930-01"))
        model.code = " lav-260930-01 "

        #expect(model.create(context: ctx) == nil)
        #expect(try ctx.fetch(FetchDescriptor<Batch>()).count == 1)
    }

    /// The refusal comes before any purchase is drawn from.
    @Test func create_DuplicateCode_LeavesInventoryUntouched() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let stock = purchase(ctx, for: oil, quantity: 2000, totalPrice: 20, daysAgo: 3)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)
        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        ctx.insert(Batch.mock(code: "2026/14"))
        model.code = "2026/14"

        #expect(model.canCreate)
        #expect(model.create(context: ctx) == nil)
        #expect(abs(stock.remainingAmount - 2000) < 1e-9)
        #expect(stock.openingDate == nil)
        #expect(try ctx.fetch(FetchDescriptor<BatchLineItem>()).isEmpty)
    }

    @Test func create_CodeFreedByChangingIt_Creates() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModel(ctx)
        ctx.insert(Batch.mock(code: "2026/14"))
        model.code = "2026/14"
        #expect(model.create(context: ctx) == nil)

        model.code = "2026/15"
        let batch = try #require(model.create(context: ctx))

        #expect(batch.code == "2026/15")
    }

    /// No sheet prepared a code — the batch still leaves with one.
    @Test func create_CodeNeverSuggested_GeneratesOne() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModel(ctx)
        let now = Date.now

        let batch = try #require(model.create(context: ctx, date: now))

        #expect(batch.code == expectedCode(on: now))
    }

    @Test func create_CodeCleared_GeneratesOnePastThoseInTheStore() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModel(ctx)
        let now = Date.now
        let taken = expectedCode(on: now)
        ctx.insert(Batch.mock(code: taken))
        try ctx.save()
        model.suggestCode(existingCodes: [taken], date: now)
        model.code = "   "

        let batch = try #require(model.create(context: ctx, date: now))

        #expect(batch.code == expectedCode(on: now, existingCodes: [taken]))
        #expect(batch.code != taken)
    }

    @Test func create_TwiceInARow_GivesEachBatchItsOwnCode() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModel(ctx)
        let now = Date.now

        let first = try #require(model.create(context: ctx, date: now))
        let second = try #require(model.create(context: ctx, date: now))

        #expect(first.code != second.code)
        #expect(BatchCodeGenerator.isTaken(second.code, among: [first, second], excluding: second) == false)
    }

    // MARK: - After creating

    /// The sheet is still on screen while it closes, with the new batch already
    /// in the store under the code the field shows.
    @Test func codeIsTaken_AfterCreating_DoesNotCountTheBatchJustMade() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModel(ctx)
        model.code = "2026/14"

        let batch = try #require(model.create(context: ctx))

        #expect(model.codeIsTaken(among: [batch]) == false)
    }

    @Test func codeIsTaken_AfterCreating_StillCountsOtherBatches() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModel(ctx)
        model.code = "2026/14"
        let batch = try #require(model.create(context: ctx))
        let other = Batch.mock(code: "2026/14")

        #expect(model.codeIsTaken(among: [batch, other]))
    }

    @Test func suggestCode_AfterCreating_LeavesTheCodeAlone() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModel(ctx)
        let now = Date.now
        model.suggestCode(existingCodes: [], date: now)
        let batch = try #require(model.create(context: ctx, date: now))

        model.suggestCode(existingCodes: [batch.code], date: now)

        #expect(model.code == batch.code)
        #expect(model.suggestedCode == batch.code)
    }

    /// Not counting the batch just made is for the closing sheet only — it
    /// must not let the same model make a second batch under that code.
    @Test func create_AgainWithTheSameTypedCode_CreatesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = makeModel(ctx)
        model.code = "2026/14"
        _ = try #require(model.create(context: ctx))

        #expect(model.create(context: ctx) == nil)
        #expect(try ctx.fetch(FetchDescriptor<Batch>()).count == 1)
    }

    @Test func create_InsufficientStock_CreatesNoBatchAndNoCode() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let recipe = makeRecipe(ctx, oil: oil, oilWeight: 1000)
        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        model.suggestCode(existingCodes: [])

        #expect(model.create(context: ctx) == nil)
        #expect(try ctx.fetch(FetchDescriptor<Batch>()).isEmpty)
    }
}
