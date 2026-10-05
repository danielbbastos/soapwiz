import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The detail screens' sheets, presented above the tabs so they outlive a width
/// change (SW-218): the request round trip through `AppNavigation`, and the
/// check that closes a sheet whose model has left the store.
@Suite("DetailSheetRequest")
@MainActor
struct DetailSheetRequestTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    private func makeRecipe(_ ctx: ModelContext) throws -> Recipe {
        let recipe = Recipe(name: "Castile")
        ctx.insert(recipe)
        try ctx.save()
        return recipe
    }

    private func makeIngredient(_ ctx: ModelContext, slug: String = "") throws -> Ingredient {
        let ingredient = Ingredient(name: "Olive Butter", unit: IngredientUnit.grams.rawValue)
        ingredient.librarySlug = slug
        ctx.insert(ingredient)
        try ctx.save()
        return ingredient
    }

    // MARK: - Round trip

    @Test func createBatch_RecordsTheRecipesID() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = try makeRecipe(ctx)

        let request = DetailSheetRequest.createBatch(recipe)

        #expect(request.targetID == recipe.persistentModelID)
        guard case .createBatch(let carried) = request.kind else {
            Issue.record("Expected a create-batch request")
            return
        }
        #expect(carried === recipe)
    }

    @Test func addPurchase_RecordsTheIngredientsID() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = try makeIngredient(ctx)

        let request = DetailSheetRequest.addPurchase(ingredient)

        #expect(request.targetID == ingredient.persistentModelID)
        guard case .addPurchase(let carried) = request.kind else {
            Issue.record("Expected an add-purchase request")
            return
        }
        #expect(carried === ingredient)
    }

    @Test func editIngredient_RecordsTheIngredientsID() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = try makeIngredient(ctx)

        let request = DetailSheetRequest.editIngredient(ingredient)

        #expect(request.targetID == ingredient.persistentModelID)
        guard case .editIngredient(let carried) = request.kind else {
            Issue.record("Expected an edit-ingredient request")
            return
        }
        #expect(carried === ingredient)
    }

    @Test func requests_ForTheSameModel_AreDistinct() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = try makeRecipe(ctx)

        #expect(DetailSheetRequest.createBatch(recipe).id != DetailSheetRequest.createBatch(recipe).id)
    }

    @Test func closeDetailSheet_MatchingRequest_ClearsIt() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let sut = AppNavigation()
        let request = DetailSheetRequest.createBatch(try makeRecipe(ctx))
        sut.detailSheetRequest = request

        sut.closeDetailSheet(request.id)

        #expect(sut.detailSheetRequest == nil)
    }

    /// A gone sheet's late close mustn't take down the one that replaced it.
    @Test func closeDetailSheet_ReplacedRequest_KeepsTheNewOne() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = try makeIngredient(ctx)
        let sut = AppNavigation()
        let old = DetailSheetRequest.addPurchase(ingredient)
        let new = DetailSheetRequest.editIngredient(ingredient)
        sut.detailSheetRequest = new

        sut.closeDetailSheet(old.id)

        #expect(sut.detailSheetRequest?.id == new.id)
    }

    @Test func closeDetailSheet_NothingOpen_StaysClosed() {
        let sut = AppNavigation()

        sut.closeDetailSheet(UUID())

        #expect(sut.detailSheetRequest == nil)
    }

    // MARK: - Model left the store

    /// What `DetailSheetHost`'s query sees through the request's predicate: the
    /// sheet stays up while this is true and closes once it isn't.
    private func gateMatches(_ request: DetailSheetRequest, in ctx: ModelContext) throws -> Bool {
        switch request.kind {
        case .createBatch:
            try ctx.fetchCount(FetchDescriptor(predicate: DetailSheetRequest.recipe(id: request.targetID))) > 0
        case .addPurchase, .editIngredient:
            try ctx.fetchCount(FetchDescriptor(predicate: DetailSheetRequest.ingredient(id: request.targetID))) > 0
        }
    }

    @Test func gate_RecipeStillStored_Matches() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let request = DetailSheetRequest.createBatch(try makeRecipe(ctx))

        #expect(try gateMatches(request, in: ctx))
    }

    @Test func gate_RecipeDeleted_StopsMatching() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = try makeRecipe(ctx)
        let request = DetailSheetRequest.createBatch(recipe)

        ctx.delete(recipe)
        try ctx.save()

        #expect(try gateMatches(request, in: ctx) == false)
    }

    @Test func gate_IngredientStillStored_Matches() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = try makeIngredient(ctx)

        #expect(try gateMatches(.addPurchase(ingredient), in: ctx))
        #expect(try gateMatches(.editIngredient(ingredient), in: ctx))
    }

    @Test func gate_IngredientDeleted_StopsMatching() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = try makeIngredient(ctx)
        let addPurchase = DetailSheetRequest.addPurchase(ingredient)
        let edit = DetailSheetRequest.editIngredient(ingredient)

        ctx.delete(ingredient)
        try ctx.save()

        #expect(try gateMatches(addPurchase, in: ctx) == false)
        #expect(try gateMatches(edit, in: ctx) == false)
    }

    /// Merged away counts as gone even with a surviving copy: the forms read the
    /// captured row, so the sheet closes rather than follow the survivor.
    @Test func gate_IngredientMergedAwayWithSurvivor_StopsMatching() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let survivor = try makeIngredient(ctx, slug: "olive-butter")
        let merged = try makeIngredient(ctx, slug: "olive-butter")
        let request = DetailSheetRequest.addPurchase(merged)

        ctx.delete(merged)
        try ctx.save()

        #expect(try gateMatches(request, in: ctx) == false)
        #expect(try gateMatches(.addPurchase(survivor), in: ctx))
    }

    /// Another model's deletion leaves the request alone.
    @Test func gate_OtherIngredientDeleted_StillMatches() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let kept = try makeIngredient(ctx)
        let other = try makeIngredient(ctx)
        let request = DetailSheetRequest.editIngredient(kept)

        ctx.delete(other)
        try ctx.save()

        #expect(try gateMatches(request, in: ctx))
    }

    // MARK: - A model not saved yet

    /// An ingredient added a moment ago carries a temporary id until it is
    /// saved. The request saves first, so the id it holds is the lasting one
    /// and the sheet isn't closed under the user when autosave runs.
    @Test func addPurchase_UnsavedIngredient_StillMatchesAfterTheNextSave() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Kaolin", unit: IngredientUnit.grams.rawValue)
        ctx.insert(ingredient)

        let request = DetailSheetRequest.addPurchase(ingredient)
        try ctx.save()

        #expect(request.targetID == ingredient.persistentModelID)
        #expect(try gateMatches(request, in: ctx))
    }

    @Test func editIngredient_UnsavedIngredient_SavesTheContext() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Kaolin", unit: IngredientUnit.grams.rawValue)
        ctx.insert(ingredient)

        _ = DetailSheetRequest.editIngredient(ingredient)

        #expect(ctx.hasChanges == false)
    }

    @Test func createBatch_UnsavedRecipe_StillMatchesAfterTheNextSave() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Castile")
        ctx.insert(recipe)

        let request = DetailSheetRequest.createBatch(recipe)
        try ctx.save()

        #expect(try gateMatches(request, in: ctx))
    }

    // MARK: - Waiting for a file to open

    /// A recipe file opened from another app waits for a detail sheet, since
    /// the import review can't go up over it, and is handed out once the sheet
    /// has finished closing.
    @Test func takePendingRecipeFileImport_DetailSheetUp_HoldsTheFileUntilItCloses() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let sut = AppNavigation()
        sut.detailSheetRequest = .createBatch(try makeRecipe(ctx))
        sut.openRecipeFile(URL(fileURLWithPath: "/tmp/shared.soapwizrecipe"))
        let opened = try #require(sut.pendingRecipeFileImport)

        #expect(sut.takePendingRecipeFileImport() == nil)

        sut.detailSheetRequest = nil
        #expect(sut.isDetailSheetOnScreen)
        #expect(sut.takePendingRecipeFileImport() == nil)

        sut.detailSheetDidClose()

        #expect(sut.isDetailSheetOnScreen == false)
        #expect(sut.detailSheetClosings == 1)
        #expect(sut.takePendingRecipeFileImport() == opened)
    }

    /// Reopened during the closing animation: the first sheet's dismissal
    /// lands while the second is waiting to go up, and the file must keep
    /// waiting for that one too.
    @Test func detailSheetDidClose_NewRequestWhileClosing_StaysOnScreen() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = try makeIngredient(ctx)
        let sut = AppNavigation()
        sut.detailSheetRequest = .addPurchase(ingredient)
        sut.detailSheetRequest = nil
        sut.detailSheetRequest = .addPurchase(ingredient)
        sut.openRecipeFile(URL(fileURLWithPath: "/tmp/shared.soapwizrecipe"))

        sut.detailSheetDidClose()

        #expect(sut.isDetailSheetOnScreen)
        #expect(sut.takePendingRecipeFileImport() == nil)
    }

    @Test func discardDetailSheet_ClearsTheSheetAtOnce() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let sut = AppNavigation()
        sut.detailSheetRequest = .createBatch(try makeRecipe(ctx))

        sut.discardDetailSheet()

        #expect(sut.detailSheetRequest == nil)
        #expect(sut.isDetailSheetOnScreen == false)
    }
}
