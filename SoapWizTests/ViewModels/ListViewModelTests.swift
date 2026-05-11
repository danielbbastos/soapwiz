import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import SoapWiz

@Suite("List ViewModels")
@MainActor
struct ListViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientBatch.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    @Test func categoryDeleteBlockedWhenIngredientsAssigned() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let category = IngredientCategory(name: "Oils")
        ctx.insert(category)
        let ingredient = Ingredient(name: "Olive Oil", category: category, unit: "g")
        ctx.insert(ingredient)
        try ctx.save()

        let model = CategoryListViewModel()
        model.delete(at: IndexSet(integer: 0), in: [category], context: ctx)
        #expect(model.deleteBlockedCategory === category)

        let remaining = try ctx.fetch(FetchDescriptor<IngredientCategory>())
        #expect(remaining.count == 1)
    }

    @Test func categoryDeleteSucceedsWhenEmpty() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let category = IngredientCategory(name: "Oils")
        ctx.insert(category)
        try ctx.save()

        let model = CategoryListViewModel()
        model.delete(at: IndexSet(integer: 0), in: [category], context: ctx)
        try ctx.save()
        #expect(model.deleteBlockedCategory == nil)

        let remaining = try ctx.fetch(FetchDescriptor<IngredientCategory>())
        #expect(remaining.isEmpty)
    }

    @Test func storageLocationDeleteBlockedWhenBatchesAssigned() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(ingredient)
        let location = StorageLocation(name: "Shelf A")
        ctx.insert(location)
        let batch = IngredientBatch(
            dateOfPurchase: .now, quantity: 100, totalPrice: 10,
            badge: "", journalCode: "", expiryDate: nil, openingDate: nil,
            storageLocation: location
        )
        ctx.insert(batch)
        ingredient.batches.append(batch)
        try ctx.save()

        let model = StorageLocationListViewModel()
        model.delete(at: IndexSet(integer: 0), in: [location], context: ctx)
        #expect(model.deleteBlockedLocation === location)
    }

    @Test func providerDeleteBlockedWhenBatchesAssigned() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(ingredient)
        let provider = Provider(name: "Acme")
        ctx.insert(provider)
        let batch = IngredientBatch(
            provider: provider,
            dateOfPurchase: .now, quantity: 100, totalPrice: 10,
            badge: "", journalCode: "", expiryDate: nil, openingDate: nil
        )
        ctx.insert(batch)
        ingredient.batches.append(batch)
        try ctx.save()

        let model = ProviderListViewModel()
        model.delete(at: IndexSet(integer: 0), in: [provider], context: ctx)
        #expect(model.deleteBlockedProvider === provider)
    }

    @Test func ingredientDeleteAtOffsets() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let a = Ingredient(name: "A", unit: "g")
        let b = Ingredient(name: "B", unit: "g")
        ctx.insert(a); ctx.insert(b)
        try ctx.save()

        let model = IngredientListViewModel()
        model.delete(at: IndexSet(integer: 0), in: [a, b], context: ctx)
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<Ingredient>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.name == "B")
    }

    @Test func ingredientDeleteSelectedClearsStateAndExitsEditMode() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let a = Ingredient(name: "A", unit: "g")
        ctx.insert(a)
        try ctx.save()

        let model = IngredientListViewModel()
        model.editMode = .active
        model.selection = [a.persistentModelID]
        model.deleteSelected(in: [a], context: ctx)

        #expect(model.selection.isEmpty)
        #expect(model.editMode == .inactive)
    }
}
