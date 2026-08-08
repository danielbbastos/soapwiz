import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The narrow product-only save path the recipe detail screen writes through.
@Suite("RecipeForm – product-only save", .serialized)
@MainActor
struct RecipeProductPersistenceTests: RecipeFormTestHelpers {

    @Test func saveProducts_AddedDraft_PersistsProduct() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeLoadedModel(ctx: ctx)

        model.productDrafts.append(RecipeProductDraft(size: 100, unitSymbol: ProductUnit.grams.rawValue))
        try model.saveProducts(context: ctx)

        let recipe = try #require(model.editingRecipe)
        let added = try #require(recipe.products.first { $0.unitSymbol == ProductUnit.grams.rawValue })
        #expect(added.size == 100)
        #expect(recipe.products.count == 2)
    }

    @Test func saveProducts_AddedDraft_StampsPermanentModelID() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeLoadedModel(ctx: ctx)

        model.productDrafts.append(RecipeProductDraft(size: 100, unitSymbol: ProductUnit.grams.rawValue))
        try model.saveProducts(context: ctx)

        let recipe = try #require(model.editingRecipe)
        let added = try #require(recipe.products.first { $0.unitSymbol == ProductUnit.grams.rawValue })
        let draft = try #require(model.productDrafts.last)
        #expect(draft.modelID == added.persistentModelID)
    }

    @Test func saveProducts_RemovedDraft_DeletesProduct() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeLoadedModel(ctx: ctx)
        model.productDrafts.append(RecipeProductDraft(size: 100, unitSymbol: ProductUnit.grams.rawValue))
        try model.saveProducts(context: ctx)

        model.productDrafts.removeAll { $0.unitSymbol == ProductUnit.grams.rawValue }
        try model.saveProducts(context: ctx)

        let recipe = try #require(model.editingRecipe)
        #expect(recipe.products.count == 1)
        #expect(recipe.products.allSatisfy { $0.unitSymbol == ProductUnit.partsOfBatch.rawValue })
        #expect(try ctx.fetch(FetchDescriptor<RecipeProduct>()).count == 1)
    }

    @Test func saveProducts_RemovedLastDraft_LeavesRecipeWithNoProducts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeLoadedModel(ctx: ctx)

        model.productDrafts.removeAll()
        try model.saveProducts(context: ctx)

        let recipe = try #require(model.editingRecipe)
        #expect(recipe.products.isEmpty)
        // No placeholder draft is reinstated — one would be persisted by the
        // next save as a product the user never asked for.
        #expect(model.productDrafts.isEmpty)
    }

    @Test func saveProducts_RepeatedSaves_KeepProductIdentityStable() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeLoadedModel(ctx: ctx)
        model.productDrafts.append(RecipeProductDraft(size: 100, unitSymbol: ProductUnit.grams.rawValue))
        try model.saveProducts(context: ctx)

        let recipe = try #require(model.editingRecipe)
        let before = Set(recipe.products.map(\.persistentModelID))
        try model.saveProducts(context: ctx)

        #expect(Set(recipe.products.map(\.persistentModelID)) == before)
    }

    @Test func saveProducts_EditedDraft_UpdatesInPlace() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeLoadedModel(ctx: ctx)
        model.productDrafts.append(RecipeProductDraft(size: 100, unitSymbol: ProductUnit.grams.rawValue))
        try model.saveProducts(context: ctx)
        let recipe = try #require(model.editingRecipe)
        let originalID = try #require(model.productDrafts.last?.modelID)

        model.productDrafts[model.productDrafts.count - 1].size = 250
        try model.saveProducts(context: ctx)

        let updated = try #require(recipe.products.first { $0.persistentModelID == originalID })
        #expect(updated.size == 250)
        #expect(recipe.products.count == 2)
    }

    @Test func saveProducts_NoEditingRecipe_DoesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()

        model.productDrafts.append(RecipeProductDraft(size: 100, unitSymbol: ProductUnit.grams.rawValue))
        try model.saveProducts(context: ctx)

        #expect(try ctx.fetch(FetchDescriptor<RecipeProduct>()).isEmpty)
    }

    // MARK: - The seeded placeholder is never persisted

    @Test func saveProducts_ProductlessRecipe_PersistsOnlyTheAddedProduct() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeProductlessModel(ctx: ctx)
        // `load` seeds a placeholder row so the form has something to show.
        #expect(model.productDrafts.count == 1)
        #expect(try #require(model.productDrafts.first).isSeededPlaceholder)

        model.productDrafts.append(RecipeProductDraft(size: 100, unitSymbol: ProductUnit.grams.rawValue))
        try model.saveProducts(context: ctx)

        let recipe = try #require(model.editingRecipe)
        #expect(recipe.products.count == 1)
        #expect(recipe.products.first?.unitSymbol == ProductUnit.grams.rawValue)
    }

    @Test func save_ProductlessRecipe_DoesNotPersistPlaceholder() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeProductlessModel(ctx: ctx)

        model.save(context: ctx)

        let recipe = try #require(model.editingRecipe)
        #expect(recipe.products.isEmpty)
    }

    @Test func saveProducts_UserAuthoredPartsOfBatch_IsPersisted() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeProductlessModel(ctx: ctx)

        // Same unit as the placeholder, but a size the user chose.
        model.productDrafts.append(RecipeProductDraft(size: 4, unitSymbol: ProductUnit.partsOfBatch.rawValue))
        try model.saveProducts(context: ctx)

        let recipe = try #require(model.editingRecipe)
        #expect(recipe.products.count == 1)
        #expect(recipe.products.first?.size == 4)
    }

    @Test func isSeededPlaceholder_SavedSinglePartBatchRow_IsNotAPlaceholder() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeProductlessModel(ctx: ctx)
        model.productDrafts = [RecipeProductDraft(size: 4, unitSymbol: ProductUnit.partsOfBatch.rawValue)]
        try model.saveProducts(context: ctx)

        // Shrinking a real product back to a single part must not make it
        // vanish on the next save — the row was never the seeded one.
        model.productDrafts[0].size = 1
        #expect(model.productDrafts[0].isSeededPlaceholder == false)
        try model.saveProducts(context: ctx)

        let recipe = try #require(model.editingRecipe)
        #expect(recipe.products.count == 1)
        #expect(recipe.products.first?.size == 1)
    }

    @Test func saveProducts_AddedRowSnappedToASinglePart_IsPersisted() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeProductlessModel(ctx: ctx)

        // What the card's unit popover does to a freshly added row: picking a
        // unit that needs a size snaps an unset size to 1, which leaves the row
        // shaped exactly like the seeded placeholder. It is still the user's
        // product and has to be saved.
        model.addProduct(defaultUnitSymbol: ProductUnit.grams.rawValue)
        let index = model.productDrafts.count - 1
        model.productDrafts[index].unitSymbol = ProductUnit.partsOfBatch.rawValue
        model.productDrafts[index].size = 1
        #expect(model.productDrafts[index].isSeededPlaceholder == false)
        try model.saveProducts(context: ctx)

        let recipe = try #require(model.editingRecipe)
        #expect(recipe.products.count == 1)
        #expect(recipe.products.first?.unitSymbol == ProductUnit.partsOfBatch.rawValue)
        #expect(recipe.products.first?.size == 1)
    }

    @Test func saveProducts_ResizedPlaceholder_IsPersisted() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeProductlessModel(ctx: ctx)

        model.productDrafts[0].size = 4
        #expect(model.productDrafts[0].isSeededPlaceholder == false)
        try model.saveProducts(context: ctx)

        let recipe = try #require(model.editingRecipe)
        #expect(recipe.products.count == 1)
        #expect(recipe.products.first?.size == 4)
    }

    @Test func saveProducts_PlaceholderGivenAnotherUnit_IsPersisted() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeProductlessModel(ctx: ctx)

        model.productDrafts[0].unitSymbol = ProductUnit.grams.rawValue
        #expect(model.productDrafts[0].isSeededPlaceholder == false)
        try model.saveProducts(context: ctx)

        let recipe = try #require(model.editingRecipe)
        #expect(recipe.products.count == 1)
        #expect(recipe.products.first?.unitSymbol == ProductUnit.grams.rawValue)
    }

    @Test func isSeededPlaceholder_RewrittenWithTheSameValues_StaysMarked() {
        // A SwiftUI binding writes on every pass, same value or not; only a real
        // change hands the row to the user.
        var draft = RecipeProductDraft.seededPlaceholder()
        draft.size = 1
        draft.unitSymbol = ProductUnit.partsOfBatch.rawValue

        #expect(draft.isSeededPlaceholder)
    }

    @Test func isSeededPlaceholder_DraftBuiltByHand_IsFalse() {
        #expect(RecipeProductDraft(size: 1, unitSymbol: ProductUnit.partsOfBatch.rawValue).isSeededPlaceholder == false)
    }

    // MARK: - Ingredients are untouched

    @Test func saveProducts_AddedDraft_LeavesIngredientsUntouched() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeLoadedModel(ctx: ctx)
        let recipe = try #require(model.editingRecipe)
        let before = Set(recipe.ingredients.map(\.persistentModelID))
        #expect(before.count == 2)

        model.productDrafts.append(RecipeProductDraft(size: 100, unitSymbol: ProductUnit.grams.rawValue))
        try model.saveProducts(context: ctx)

        // A full `save(context:)` deletes and reinserts every line item; the
        // narrow path must leave the very same rows in place.
        #expect(Set(recipe.ingredients.map(\.persistentModelID)) == before)
        #expect(try ctx.fetch(FetchDescriptor<RecipeIngredient>()).count == 2)
    }

    @Test func saveProducts_RemovedDraft_LeavesIngredientsUntouched() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeLoadedModel(ctx: ctx)
        model.productDrafts.append(RecipeProductDraft(size: 100, unitSymbol: ProductUnit.grams.rawValue))
        try model.saveProducts(context: ctx)
        let recipe = try #require(model.editingRecipe)
        let before = Set(recipe.ingredients.map(\.persistentModelID))

        model.productDrafts.removeAll { $0.unitSymbol == ProductUnit.grams.rawValue }
        try model.saveProducts(context: ctx)

        #expect(Set(recipe.ingredients.map(\.persistentModelID)) == before)
        #expect(try ctx.fetch(FetchDescriptor<RecipeIngredient>()).count == 2)
    }

    @Test func saveProducts_AddedDraft_LeavesIngredientAmountsUnchanged() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeLoadedModel(ctx: ctx)
        let recipe = try #require(model.editingRecipe)

        model.productDrafts.append(RecipeProductDraft(size: 100, unitSymbol: ProductUnit.grams.rawValue))
        try model.saveProducts(context: ctx)

        let oil = try #require(recipe.ingredients.first { $0.ingredientRole == .oil })
        let additive = try #require(recipe.ingredients.first { $0.ingredientRole == .additive })
        #expect(oil.percentage == 100)
        #expect(additive.additiveAmount == 30)
        #expect(additive.additiveUnit == "g")
    }

    // MARK: - Full save shares the same reconciliation

    @Test func save_ExistingProduct_KeepsItsIdentity() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeLoadedModel(ctx: ctx)
        let recipe = try #require(model.editingRecipe)
        let before = try #require(recipe.products.first?.persistentModelID)

        model.save(context: ctx)

        #expect(recipe.products.count == 1)
        #expect(recipe.products.first?.persistentModelID == before)
    }

    // MARK: - Helpers

    /// A saved recipe with one oil, one additive and one real product (a
    /// quarter-batch, not the seeded placeholder), loaded into a view model the
    /// way the detail screen loads it.
    private func makeLoadedModel(ctx: ModelContext) throws -> RecipeFormViewModel {
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        ctx.insert(oil)
        let additive = Ingredient(name: "Kaolin Clay")
        ctx.insert(additive)

        let model = RecipeFormViewModel()
        model.name = "Test Recipe"
        model.totalOilWeight = 1000
        model.oilWeightUnit = "g"
        model.addOil(oil)
        model.oilDrafts[0].amount = 100
        model.additiveDrafts.append(IngredientAmountDraft(ingredient: additive, amount: 30, unit: "g"))
        model.productDrafts = [RecipeProductDraft(size: 4, unitSymbol: ProductUnit.partsOfBatch.rawValue)]

        let recipe = model.save(context: ctx)
        try ctx.save()

        let loaded = RecipeFormViewModel()
        loaded.load(from: recipe)
        return loaded
    }

    /// A saved recipe with an oil but no products at all, loaded into a view
    /// model — so `load` seeds its placeholder draft.
    private func makeProductlessModel(ctx: ModelContext) throws -> RecipeFormViewModel {
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        ctx.insert(oil)

        let recipe = Recipe(name: "No products", desc: "")
        ctx.insert(recipe)
        let line = RecipeIngredient(ingredient: oil, percentage: 100, role: .oil)
        line.recipe = recipe
        ctx.insert(line)
        try ctx.save()
        #expect(recipe.products.isEmpty)

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        return model
    }
}
