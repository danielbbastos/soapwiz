import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Deleting an ingredient a recipe uses silently corrupts that recipe — line items
/// cascade away and lye links nullify, leaving oil percentages that no longer sum
/// and a lye figure calculated from the remainder. Deletion is blocked instead.
@Suite("Ingredient delete guard", .serialized)
@MainActor
struct IngredientDeleteGuardTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            Ingredient.self, IngredientPurchase.self, IngredientCategory.self,
            StorageLocation.self, Provider.self,
            Recipe.self, RecipeIngredient.self, RecipeProduct.self,
            Batch.self, BatchLineItem.self, AppSettings.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    // MARK: - Ingredient.recipesUsingThis

    @Test func recipesUsingThis_UnusedIngredient_IsEmpty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(olive)
        try ctx.save()

        #expect(olive.recipesUsingThis.isEmpty)
        #expect(olive.isUsedInRecipes == false)
    }

    @Test func recipesUsingThis_LineItem_IsFound() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        let recipe = Recipe(name: "Bastille")
        ctx.insert(olive)
        ctx.insert(recipe)
        let line = RecipeIngredient(ingredient: olive, percentage: 100, role: .oil)
        line.recipe = recipe
        ctx.insert(line)
        try ctx.save()

        #expect(olive.recipesUsingThis.map(\.name) == ["Bastille"])
        #expect(olive.isUsedInRecipes)
    }

    @Test func recipesUsingThis_NaOHLye_IsFound() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let naoh = Ingredient(name: "Sodium Hydroxide", unit: "g")
        let recipe = Recipe(name: "Bastille")
        recipe.lyeIngredient = naoh
        ctx.insert(naoh)
        ctx.insert(recipe)
        try ctx.save()

        #expect(naoh.recipesUsingThis.map(\.name) == ["Bastille"])
    }

    @Test func recipesUsingThis_KOHLye_IsFound() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let koh = Ingredient(name: "Potassium Hydroxide", unit: "g")
        let recipe = Recipe(name: "Liquid Soap")
        recipe.kohLyeIngredient = koh
        ctx.insert(koh)
        ctx.insert(recipe)
        try ctx.save()

        #expect(koh.recipesUsingThis.map(\.name) == ["Liquid Soap"])
    }

    /// An ingredient can be both a line item and the lye of the same recipe.
    /// Reporting "used in 2 recipes" for one recipe would be wrong.
    @Test func recipesUsingThis_LineItemAndLyeInSameRecipe_CountsRecipeOnce() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let dual = Ingredient(name: "Dual Purpose", unit: "g")
        let recipe = Recipe(name: "Bastille")
        recipe.lyeIngredient = dual
        ctx.insert(dual)
        ctx.insert(recipe)
        let line = RecipeIngredient(ingredient: dual, percentage: 100, role: .oil)
        line.recipe = recipe
        ctx.insert(line)
        try ctx.save()

        #expect(dual.recipesUsingThis.count == 1)
    }

    /// Batch history snapshots names and costs, so it stays readable without the
    /// ingredient. Blocking on batch usage would make ingredients undeletable forever.
    @Test func recipesUsingThis_OnlyUsedByPastBatch_IsEmpty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        let batch = Batch(recipe: nil, recipeName: "Bastille", batchCount: 1)
        ctx.insert(olive)
        ctx.insert(batch)
        let item = BatchLineItem(
            ingredient: olive, ingredientName: "Olive Oil",
            amountConsumed: 500, unit: "g", cost: 4, draws: []
        )
        item.batch = batch
        ctx.insert(item)
        try ctx.save()

        #expect(olive.recipesUsingThis.isEmpty)
        #expect(olive.isUsedInRecipes == false)
    }

    // MARK: - Single delete

    @Test func delete_IngredientUsedByRecipe_IsBlockedAndNotDeleted() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        let recipe = Recipe(name: "Bastille")
        ctx.insert(olive)
        ctx.insert(recipe)
        let line = RecipeIngredient(ingredient: olive, percentage: 100, role: .oil)
        line.recipe = recipe
        ctx.insert(line)
        try ctx.save()

        let model = IngredientListViewModel()
        model.delete(olive)
        try ctx.save()

        #expect(model.deleteBlockedIngredients.map(\.name) == ["Olive Oil"])
        #expect(model.confirmingDelete.isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<RecipeIngredient>()).count == 1)
    }

    /// Recipe usage outranks the has-stock confirmation: lost stock is recoverable,
    /// a silently gutted recipe is not.
    @Test func delete_UsedByRecipeAndHasStock_BlocksRatherThanConfirms() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        let recipe = Recipe(name: "Bastille")
        ctx.insert(olive)
        ctx.insert(recipe)
        let purchase = IngredientPurchase(
            dateOfPurchase: .now, quantity: 1000, totalPrice: 8,
            badge: "L1", journalCode: "J1", expiryDate: nil, openingDate: nil
        )
        purchase.ingredient = olive
        ctx.insert(purchase)
        let line = RecipeIngredient(ingredient: olive, percentage: 100, role: .oil)
        line.recipe = recipe
        ctx.insert(line)
        try ctx.save()

        let model = IngredientListViewModel()
        model.delete(olive)

        #expect(model.deleteBlockedIngredients.count == 1)
        #expect(model.confirmingDelete.isEmpty)
    }

    /// Nothing is deleted on a single tap. An ingredient with no stock still holds sap
    /// values, density and a fatty-acid profile, and there is no undo — an accidental
    /// swipe must not destroy it.
    @Test func delete_UnusedWithNoPurchases_AsksForConfirmationAndKeepsIt() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(olive)
        try ctx.save()

        let model = IngredientListViewModel()
        model.delete(olive)
        try ctx.save()

        #expect(model.deleteBlockedIngredients.isEmpty)
        #expect(model.confirmingDelete.map(\.name) == ["Olive Oil"])
        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).count == 1)
    }

    @Test func confirmDelete_AfterConfirmation_ActuallyDeletes() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(olive)
        try ctx.save()

        let model = IngredientListViewModel()
        model.delete(olive)
        model.confirmDelete(context: ctx)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).isEmpty)
        #expect(model.confirmingDelete.isEmpty)
    }

    @Test func delete_UnusedWithPurchases_StillAsksForConfirmation() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(olive)
        let purchase = IngredientPurchase(
            dateOfPurchase: .now, quantity: 1000, totalPrice: 8,
            badge: "L1", journalCode: "J1", expiryDate: nil, openingDate: nil
        )
        purchase.ingredient = olive
        ctx.insert(purchase)
        try ctx.save()

        let model = IngredientListViewModel()
        model.delete(olive)

        #expect(model.deleteBlockedIngredients.isEmpty)
        #expect(model.confirmingDelete.map(\.name) == ["Olive Oil"])
    }

    // MARK: - Multi-select delete

    @Test func deleteSelected_OneOfSeveralIsUsed_DeletesNone() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        let coconut = Ingredient(name: "Coconut Oil", unit: "g")
        let recipe = Recipe(name: "Bastille")
        [olive, coconut].forEach { ctx.insert($0) }
        ctx.insert(recipe)
        let line = RecipeIngredient(ingredient: olive, percentage: 100, role: .oil)
        line.recipe = recipe
        ctx.insert(line)
        try ctx.save()

        let model = IngredientListViewModel()
        model.selection = [olive.persistentModelID, coconut.persistentModelID]
        model.deleteSelected(in: [olive, coconut])
        try ctx.save()

        #expect(model.deleteBlockedIngredients.map(\.name) == ["Olive Oil"])
        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).count == 2)
    }

    @Test func deleteSelected_NoneUsed_AsksForConfirmationBeforeDeleting() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        let coconut = Ingredient(name: "Coconut Oil", unit: "g")
        [olive, coconut].forEach { ctx.insert($0) }
        try ctx.save()

        let model = IngredientListViewModel()
        model.selection = [olive.persistentModelID, coconut.persistentModelID]
        model.deleteSelected(in: [olive, coconut])
        try ctx.save()

        #expect(model.deleteBlockedIngredients.isEmpty)
        #expect(model.confirmingDelete.count == 2)
        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).count == 2)

        model.confirmDelete(context: ctx)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).isEmpty)
        #expect(model.selection.isEmpty)
    }

    @Test func deleteSelected_EmptySelection_DoesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(olive)
        try ctx.save()

        let model = IngredientListViewModel()
        model.deleteSelected(in: [olive])

        #expect(model.confirmingDelete.isEmpty)
        #expect(model.deleteBlockedIngredients.isEmpty)
    }
}
