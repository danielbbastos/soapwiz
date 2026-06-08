import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import SoapWiz

@Suite("List ViewModels", .serialized)
@MainActor
struct ListViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientPurchase.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    @Test func categoryDeleteBlockedWhenIngredientsAssigned() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let category = IngredientCategory(name: "Oils")
        ctx.insert(category)
        let ingredient = Ingredient(name: "Olive Oil", category: category)
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

    @Test func storageLocationDeleteBlockedWhenPurchasesAssigned() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let location = StorageLocation(name: "Shelf A")
        ctx.insert(location)
        let purchase = IngredientPurchase(
            dateOfPurchase: .now, quantity: 100, totalPrice: 10,
            badge: "", journalCode: "", expiryDate: nil, openingDate: nil,
            storageLocation: location
        )
        ctx.insert(purchase)
        ingredient.purchases.append(purchase)
        try ctx.save()

        let model = StorageLocationListViewModel()
        model.delete(at: IndexSet(integer: 0), in: [location], context: ctx)
        #expect(model.deleteBlockedLocation === location)
    }

    @Test func providerDeleteBlockedWhenPurchasesAssigned() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let provider = Provider(name: "Acme")
        ctx.insert(provider)
        let purchase = IngredientPurchase(
            provider: provider,
            dateOfPurchase: .now, quantity: 100, totalPrice: 10,
            badge: "", journalCode: "", expiryDate: nil, openingDate: nil
        )
        ctx.insert(purchase)
        ingredient.purchases.append(purchase)
        try ctx.save()

        let model = ProviderListViewModel()
        model.delete(at: IndexSet(integer: 0), in: [provider], context: ctx)
        #expect(model.deleteBlockedProvider === provider)
    }

    @Test func ingredientDeleteAtOffsets() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let a = Ingredient(name: "A")
        let b = Ingredient(name: "B")
        ctx.insert(a); ctx.insert(b)
        try ctx.save()

        let model = IngredientListViewModel()
        model.delete(a, context: ctx)
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<Ingredient>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.name == "B")
    }

    @Test func ingredientDeleteSelectedClearsStateAndExitsEditMode() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let a = Ingredient(name: "A")
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
