import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Regression guard for SW-165: on the SW-130 two-device check, a recipe kept
/// only one of its three oils on the iPad. The Mac merged the iPad's copies of
/// Coconut and Castor away, and the iPad applied those deletions before the
/// re-pointing of its recipe rows — which a `.cascade` rule then deleted.
///
/// "Deletion arrives first" is replayed here by deleting the losing copy
/// directly, as a CloudKit import would, before the merge on this device runs.
@Suite("Duplicate merge — rows detached by a sync race", .serialized)
@MainActor
struct DuplicateMergerLinkRepairTests: DuplicateMergerIngredientHelpers {

    private func purchase(on ingredient: Ingredient, in ctx: ModelContext) -> IngredientPurchase {
        let purchase = IngredientPurchase(
            dateOfPurchase: .now,
            quantity: 500,
            totalPrice: 10,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        ctx.insert(purchase)
        purchase.ingredient = ingredient
        return purchase
    }

    private func recipe(using ingredient: Ingredient, in ctx: ModelContext) -> (Recipe, RecipeIngredient) {
        let recipe = Recipe(name: "Classic Bastille Bar")
        ctx.insert(recipe)
        let row = RecipeIngredient(ingredient: ingredient, percentage: 20, role: .oil)
        ctx.insert(row)
        row.recipe = recipe
        return (recipe, row)
    }

    // MARK: - The device scenario

    @Test func mergeAll_LoserDeletedBeforeRepointArrives_RowsLandOnTheSurvivor() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let local = try installed(coconut, 2)
        ctx.insert(local)
        let (recipe, row) = recipe(using: local, in: ctx)
        let stock = purchase(on: local, in: ctx)
        try DuplicateMerger.mergeAll(in: ctx)

        let remote = try installed(coconut, 1)
        ctx.insert(remote)
        ctx.delete(local)
        try ctx.save()

        #expect(row.modelContext != nil)
        #expect(stock.modelContext != nil)
        #expect(row.ingredient == nil)

        try DuplicateMerger.mergeAll(in: ctx)

        #expect(row.ingredient?.uuid == remote.uuid)
        #expect(stock.ingredient?.uuid == remote.uuid)
        #expect(recipe.ingredients.count == 1)
        #expect(try ctx.fetchCount(FetchDescriptor<RecipeIngredient>()) == 1)
        #expect(try ctx.fetchCount(FetchDescriptor<IngredientPurchase>()) == 1)
    }

    @Test func mergeAll_BothCopiesPresent_RepointsWithoutLosingRows() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installed(coconut, 1)
        let lose = try installed(coconut, 2)
        ctx.insert(keep)
        ctx.insert(lose)
        let (_, row) = recipe(using: lose, in: ctx)
        let stock = purchase(on: lose, in: ctx)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        #expect(row.ingredient?.uuid == keep.uuid)
        #expect(stock.ingredient?.uuid == keep.uuid)
        #expect(try ingredients(ctx).count == 1)
    }

    /// The PR review's case: the purchase is saved and its ingredient deleted
    /// before this device has run a single merge pass, so only a slug recorded
    /// at save time can bring it back.
    @Test func mergeAll_PurchaseDetachedBeforeAnyMergePass_LandsOnTheSurvivor() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let local = try installed(coconut, 2)
        ctx.insert(local)
        try ctx.save()
        let form = PurchaseFormViewModel(ingredient: local)
        form.quantityText = "500"
        try form.save(context: ctx)
        let stock = try #require(try ctx.fetch(FetchDescriptor<IngredientPurchase>()).first)

        let remote = try installed(coconut, 1)
        ctx.insert(remote)
        ctx.delete(local)
        try ctx.save()
        #expect(stock.ingredient == nil)

        try DuplicateMerger.mergeAll(in: ctx)

        #expect(stock.ingredient?.uuid == remote.uuid)
    }

    // MARK: - Slugs

    @Test func purchaseFormSave_LibraryIngredient_RecordsSlugImmediately() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = try installed(olive, 1)
        ctx.insert(ingredient)
        let form = PurchaseFormViewModel(ingredient: ingredient)
        form.quantityText = "500"

        try form.save(context: ctx)

        let stock = try #require(try ctx.fetch(FetchDescriptor<IngredientPurchase>()).first)
        #expect(stock.ingredientSlug == olive.slug)
    }

    @Test func attach_CustomIngredient_LeavesSlugEmpty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient.mock(name: "My Tallow")
        ctx.insert(ingredient)
        let stock = purchase(on: ingredient, in: ctx)

        stock.attach(to: ingredient)

        #expect(stock.ingredient === ingredient)
        #expect(stock.ingredientSlug.isEmpty)
    }

    @Test func recipeIngredientInit_LibraryIngredient_RecordsSlug() throws {
        let ingredient = try installed(olive, 1)

        let row = RecipeIngredient(ingredient: ingredient)

        #expect(row.ingredientSlug == olive.slug)
    }

    @Test func recipeIngredientInit_NilIngredient_LeavesSlugEmpty() {
        let row = RecipeIngredient(ingredient: nil)

        #expect(row.ingredientSlug.isEmpty)
    }

    @Test func mergeAll_PurchaseWithoutSlug_StampsIt() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = try installed(olive, 1)
        ctx.insert(ingredient)
        let stock = purchase(on: ingredient, in: ctx)
        try ctx.save()
        #expect(stock.ingredientSlug.isEmpty)

        try DuplicateMerger.mergeAll(in: ctx)

        #expect(stock.ingredientSlug == olive.slug)
    }

    // MARK: - Left alone

    @Test func mergeAll_DetachedRowWithoutSlug_StaysDetached() throws {
        let (container, ctx) = try makeContext()
        _ = container
        ctx.insert(try installed(olive, 1))
        let row = RecipeIngredient(ingredient: nil)
        ctx.insert(row)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        #expect(row.ingredient == nil)
    }

    @Test func mergeAll_DetachedRowWithUnknownSlug_StaysDetached() throws {
        let (container, ctx) = try makeContext()
        _ = container
        ctx.insert(try installed(olive, 1))
        let row = RecipeIngredient(ingredient: nil)
        row.ingredientSlug = coconut.slug
        ctx.insert(row)
        try ctx.save()

        try DuplicateMerger.mergeAll(in: ctx)

        #expect(row.ingredient == nil)
    }

    // MARK: - Delete rules

    @Test func deleteWithOwnedRows_RemovesPurchasesAndRecipeRows_KeepsRecipe() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient.mock(name: "My Tallow")
        ctx.insert(ingredient)
        let (recipe, _) = recipe(using: ingredient, in: ctx)
        _ = purchase(on: ingredient, in: ctx)
        try ctx.save()

        ingredient.deleteWithOwnedRows(in: ctx)
        try ctx.save()

        #expect(try ctx.fetchCount(FetchDescriptor<Ingredient>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<RecipeIngredient>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<IngredientPurchase>()) == 0)
        #expect(recipe.modelContext != nil)
    }
}
