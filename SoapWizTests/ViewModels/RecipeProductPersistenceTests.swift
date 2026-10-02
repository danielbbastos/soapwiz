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
        #expect(recipe.products.count == 3)
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
        #expect(recipe.products.count == 2)
        #expect(recipe.products.allSatisfy { $0.unitSymbol != ProductUnit.grams.rawValue })
        #expect(recipe.products.contains { $0.unitSymbol == ProductUnit.wholeBatch.rawValue })
        #expect(try ctx.fetch(FetchDescriptor<RecipeProduct>()).count == 2)
    }

    @Test func saveProducts_RemovedAllNonDefaultDrafts_LeavesOnlyWholeBatch() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeLoadedModel(ctx: ctx)

        model.productDrafts.removeAll { !$0.isWholeBatch }
        try model.saveProducts(context: ctx)

        let recipe = try #require(model.editingRecipe)
        let onlyProduct = try #require(recipe.products.first)
        #expect(recipe.products.count == 1)
        #expect(onlyProduct.unitSymbol == ProductUnit.wholeBatch.rawValue)
        let onlyDraft = try #require(model.productDrafts.first)
        #expect(model.productDrafts.count == 1)
        #expect(onlyDraft.isWholeBatch)
    }

    @Test func load_TwoStoredWholeBatchRows_KeepsOneAndSaveDeletesTheOther() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Duplicated", desc: "")
        ctx.insert(recipe)
        for (size, unit) in [(1.0, ProductUnit.wholeBatch), (100.0, ProductUnit.grams), (1.0, ProductUnit.wholeBatch)] {
            let product = RecipeProduct(size: size, unitSymbol: unit.rawValue)
            product.recipe = recipe
            ctx.insert(product)
        }
        try ctx.save()

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        try #require(model.productDrafts.count == 2)
        #expect(model.productDrafts[0].isWholeBatch)
        #expect(model.productDrafts[1].unitSymbol == ProductUnit.grams.rawValue)

        try model.saveProducts(context: ctx)

        let stored = try ctx.fetch(FetchDescriptor<RecipeProduct>())
        #expect(stored.count == 2)
        #expect(stored.count { $0.unitSymbol == ProductUnit.wholeBatch.rawValue } == 1)
    }

    @Test func load_LegacyOnePartOfBatchRow_IsReplacedByWholeBatch() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Legacy", desc: "")
        ctx.insert(recipe)
        for (size, unit) in [(1.0, ProductUnit.partsOfBatch), (100.0, ProductUnit.grams)] {
            let product = RecipeProduct(size: size, unitSymbol: unit.rawValue)
            product.recipe = recipe
            ctx.insert(product)
        }
        try ctx.save()

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        try #require(model.productDrafts.count == 2)
        #expect(model.productDrafts[0].isWholeBatch)
        #expect(model.productDrafts[0].modelID == nil)
        #expect(model.productDrafts[1].unitSymbol == ProductUnit.grams.rawValue)

        try model.saveProducts(context: ctx)

        let stored = try ctx.fetch(FetchDescriptor<RecipeProduct>())
        #expect(stored.count == 2)
        #expect(stored.count { $0.unitSymbol == ProductUnit.wholeBatch.rawValue } == 1)
        #expect(stored.count { $0.unitSymbol == ProductUnit.grams.rawValue } == 1)
        #expect(!stored.contains { $0.unitSymbol == ProductUnit.partsOfBatch.rawValue })
    }

    @Test func load_FourPartsOfBatchRow_IsKept() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeLoadedModel(ctx: ctx)

        try #require(model.productDrafts.count == 2)
        #expect(model.productDrafts[0].isWholeBatch)
        #expect(model.productDrafts[1].unitSymbol == ProductUnit.partsOfBatch.rawValue)
        #expect(model.productDrafts[1].size == 4)
    }

    @Test func save_LoadedRecipeWithWholeBatch_DoesNotAddASecond() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeLoadedModel(ctx: ctx)
        let recipe = try #require(model.editingRecipe)
        let before = try #require(model.productDrafts.first?.modelID)

        model.save(context: ctx)

        #expect(recipe.products.count { $0.unitSymbol == ProductUnit.wholeBatch.rawValue } == 1)
        #expect(model.productDrafts.first?.modelID == before)
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
        #expect(recipe.products.count == 3)
    }

    @Test func saveProducts_NoEditingRecipe_DoesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()

        model.productDrafts.append(RecipeProductDraft(size: 100, unitSymbol: ProductUnit.grams.rawValue))
        try model.saveProducts(context: ctx)

        #expect(try ctx.fetch(FetchDescriptor<RecipeProduct>()).isEmpty)
    }

    // MARK: - The whole-batch default

    @Test func load_ProductlessRecipe_StartsWithWholeBatchDefault() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeProductlessModel(ctx: ctx)

        #expect(model.productDrafts.count == 1)
        #expect(try #require(model.productDrafts.first).isWholeBatch)
        #expect(try #require(model.productDrafts.first).modelID == nil)
    }

    @Test func load_ProductlessRecipe_IsNotDirty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeProductlessModel(ctx: ctx)

        model.captureSnapshot()

        #expect(!model.isDirty)
    }

    @Test func load_WholeBatchStoredAfterAnotherSize_MovesToFront() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Sized", desc: "")
        ctx.insert(recipe)
        for (size, unit) in [(100.0, ProductUnit.grams), (1.0, ProductUnit.wholeBatch), (200.0, ProductUnit.grams)] {
            let product = RecipeProduct(size: size, unitSymbol: unit.rawValue)
            product.recipe = recipe
            ctx.insert(product)
        }
        try ctx.save()

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.productDrafts.count == 3)
        try #require(model.productDrafts.count == 3)
        #expect(model.productDrafts[0].isWholeBatch)
        #expect(model.productDrafts[0].modelID != nil)
        #expect(model.productDrafts.dropFirst().map(\.size).sorted() == [100, 200])
    }

    @Test func save_NewRecipe_WritesWholeBatchProduct() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()
        model.name = "Fresh"

        let recipe = model.save(context: ctx)

        #expect(recipe.products.count == 1)
        #expect(recipe.products.first?.unitSymbol == ProductUnit.wholeBatch.rawValue)
        #expect(recipe.products.first?.size == 1)
    }

    @Test func save_LoadedRecipeWithoutWholeBatch_WritesIt() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeProductlessModel(ctx: ctx)

        model.save(context: ctx)

        let recipe = try #require(model.editingRecipe)
        #expect(recipe.products.count == 1)
        #expect(recipe.products.first?.unitSymbol == ProductUnit.wholeBatch.rawValue)
    }

    @Test func saveProducts_ProductlessRecipe_PersistsDefaultAndAddedProduct() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = try makeProductlessModel(ctx: ctx)

        model.productDrafts.append(RecipeProductDraft(size: 100, unitSymbol: ProductUnit.grams.rawValue))
        try model.saveProducts(context: ctx)

        let recipe = try #require(model.editingRecipe)
        #expect(recipe.products.count == 2)
        #expect(recipe.products.contains { $0.unitSymbol == ProductUnit.wholeBatch.rawValue })
        #expect(recipe.products.contains { $0.unitSymbol == ProductUnit.grams.rawValue })
    }

    @Test func isWholeBatch_OtherUnit_IsFalse() {
        #expect(!RecipeProductDraft(size: 1, unitSymbol: ProductUnit.partsOfBatch.rawValue).isWholeBatch)
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

        #expect(recipe.products.count == 2)
        #expect(recipe.products.contains { $0.persistentModelID == before })
    }

    // MARK: - Helpers

    /// A saved recipe with one oil, one additive, the whole-batch default and one
    /// real product (a quarter-batch), loaded into a view model the
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
        model.productDrafts = [.wholeBatch(), RecipeProductDraft(size: 4, unitSymbol: ProductUnit.partsOfBatch.rawValue)]

        let recipe = model.save(context: ctx)
        try ctx.save()

        let loaded = RecipeFormViewModel()
        loaded.load(from: recipe)
        return loaded
    }

    /// A saved recipe with an oil but no products at all, loaded into a view
    /// model — so `load` inserts the whole-batch default.
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
