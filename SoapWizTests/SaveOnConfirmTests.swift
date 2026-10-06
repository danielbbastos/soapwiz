import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Every action that adds or deletes a row saves at once rather than leaving it
/// to autosave. Until the context saves, a screen showing the other side of the
/// relationship doesn't see the change: a purchase added to an ingredient on
/// screen appeared only seconds later.
@Suite("Save on confirm")
@MainActor
struct SaveOnConfirmTests: BackupTestHelpers {

    // MARK: - Inventory

    @Test func purchaseFormSave_NewPurchase_LeavesNothingUnsaved() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        try ctx.save()
        let model = PurchaseFormViewModel(ingredient: ingredient)
        model.quantityText = "100"
        model.totalPriceText = "25"

        try model.save(context: ctx)

        #expect(!ctx.hasChanges)
        #expect(ingredient.purchases.count == 1)
    }

    @Test func ingredientDetailDelete_Purchase_LeavesNothingUnsaved() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let purchase = IngredientPurchase(
            dateOfPurchase: .now, quantity: 100, totalPrice: 5,
            badge: "", journalCode: "", expiryDate: nil, openingDate: nil
        )
        ctx.insert(purchase)
        purchase.attach(to: ingredient)
        try ctx.save()
        let model = IngredientDetailViewModel(ingredient: ingredient)

        model.delete(at: IndexSet(integer: 0), context: ctx)

        #expect(!ctx.hasChanges)
        #expect(ingredient.purchases.isEmpty)
    }

    @Test func ingredientFormSave_NewIngredient_LeavesNothingUnsaved() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = IngredientFormViewModel()
        model.name = "Rice Bran Oil"

        let created = model.save(context: ctx)

        #expect(created != nil)
        #expect(!ctx.hasChanges)
    }

    @Test func ingredientListConfirmDelete_UserIngredient_LeavesNothingUnsaved() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ingredient = Ingredient(name: "My Oil")
        ctx.insert(ingredient)
        try ctx.save()
        let model = IngredientListViewModel()
        model.delete(ingredient)

        model.confirmDelete(context: ctx)

        #expect(!ctx.hasChanges)
        #expect(try ctx.fetchCount(FetchDescriptor<Ingredient>()) == 0)
    }

    // MARK: - Settings

    @Test func providerFormSave_NewProvider_LeavesNothingUnsaved() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = ProviderFormViewModel()
        model.name = "Soap Supplies"

        _ = model.save(context: ctx)

        #expect(!ctx.hasChanges)
    }

    @Test func providerListDelete_UnusedProvider_LeavesNothingUnsaved() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let provider = Provider(name: "Soap Supplies", website: "", notes: "")
        ctx.insert(provider)
        try ctx.save()
        let model = ProviderListViewModel()

        model.delete(at: IndexSet(integer: 0), in: [provider], context: ctx)

        #expect(!ctx.hasChanges)
        #expect(try ctx.fetchCount(FetchDescriptor<Provider>()) == 0)
    }

    // MARK: - Recipes

    @Test func recipeListDelete_Recipe_LeavesNothingUnsaved() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Castile")
        ctx.insert(recipe)
        try ctx.save()

        RecipeListViewModel().delete(recipe, context: ctx)

        #expect(!ctx.hasChanges)
        #expect(try ctx.fetchCount(FetchDescriptor<Recipe>()) == 0)
    }

    // MARK: - Batches

    @Test func batchLogEntrySave_NewEntry_LeavesNothingUnsaved() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let batch = Batch(recipe: nil, recipeName: "Castile", batchCount: 1)
        ctx.insert(batch)
        try ctx.save()
        let model = BatchLogEntryFormViewModel(batch: batch)
        model.text = "Unmoulded"

        let entry = model.save(context: ctx)

        #expect(entry != nil)
        #expect(!ctx.hasChanges)
        #expect(batch.logEntries.count == 1)
    }

    @Test func batchLogEntryDelete_Entry_LeavesNothingUnsaved() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let batch = Batch(recipe: nil, recipeName: "Castile", batchCount: 1)
        ctx.insert(batch)
        let model = BatchLogEntryFormViewModel(batch: batch)
        model.text = "Unmoulded"
        let entry = try #require(model.save(context: ctx))

        BatchLogEntryFormViewModel.delete(entry, context: ctx)

        #expect(!ctx.hasChanges)
        #expect(batch.logEntries.isEmpty)
    }

    @Test func batchCreate_EnoughStock_LeavesNothingUnsaved() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let purchase = IngredientPurchase(
            dateOfPurchase: .now, quantity: 1000, totalPrice: 10,
            badge: "", journalCode: "", expiryDate: nil, openingDate: nil
        )
        ctx.insert(purchase)
        purchase.attach(to: oil)
        let recipe = Recipe(name: "Castile")
        recipe.weightUnit = "g"
        recipe.lyePurity = 100
        recipe.superFat = 0
        ctx.insert(recipe)
        let line = RecipeIngredient(ingredient: oil, percentage: 500, role: .oil)
        line.recipe = recipe
        ctx.insert(line)
        try ctx.save()
        let model = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])

        let batch = try #require(model.create(context: ctx))

        #expect(!ctx.hasChanges)
        #expect(recipe.batches.contains { $0 === batch })
    }
}
