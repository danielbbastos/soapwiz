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

    @Test func isTargetStored_RecipeStillStored_ReturnsTrue() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let request = DetailSheetRequest.createBatch(try makeRecipe(ctx))

        #expect(request.isTargetStored(in: ctx))
    }

    @Test func isTargetStored_RecipeDeleted_ReturnsFalse() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = try makeRecipe(ctx)
        let request = DetailSheetRequest.createBatch(recipe)

        ctx.delete(recipe)
        try ctx.save()

        #expect(request.isTargetStored(in: ctx) == false)
    }

    @Test func isTargetStored_IngredientStillStored_ReturnsTrue() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = try makeIngredient(ctx)

        #expect(DetailSheetRequest.addPurchase(ingredient).isTargetStored(in: ctx))
        #expect(DetailSheetRequest.editIngredient(ingredient).isTargetStored(in: ctx))
    }

    @Test func isTargetStored_IngredientDeleted_ReturnsFalse() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = try makeIngredient(ctx)
        let addPurchase = DetailSheetRequest.addPurchase(ingredient)
        let edit = DetailSheetRequest.editIngredient(ingredient)

        ctx.delete(ingredient)
        try ctx.save()

        #expect(addPurchase.isTargetStored(in: ctx) == false)
        #expect(edit.isTargetStored(in: ctx) == false)
    }

    /// Merged away counts as gone even with a surviving copy: the forms read the
    /// captured row, so the sheet closes rather than follow the survivor.
    @Test func isTargetStored_IngredientMergedAwayWithSurvivor_ReturnsFalse() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let survivor = try makeIngredient(ctx, slug: "olive-butter")
        let merged = try makeIngredient(ctx, slug: "olive-butter")
        let request = DetailSheetRequest.addPurchase(merged)

        ctx.delete(merged)
        try ctx.save()

        #expect(request.isTargetStored(in: ctx) == false)
        #expect(DetailSheetRequest.addPurchase(survivor).isTargetStored(in: ctx))
    }

    /// Another model's deletion leaves the request alone.
    @Test func isTargetStored_OtherIngredientDeleted_ReturnsTrue() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let kept = try makeIngredient(ctx)
        let other = try makeIngredient(ctx)
        let request = DetailSheetRequest.editIngredient(kept)

        ctx.delete(other)
        try ctx.save()

        #expect(request.isTargetStored(in: ctx))
    }
}
