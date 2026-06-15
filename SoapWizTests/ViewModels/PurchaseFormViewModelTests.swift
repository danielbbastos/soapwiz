import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("PurchaseFormViewModel", .serialized)
@MainActor
struct PurchaseFormViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientPurchase.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    @Test func quantityRequiredForValid() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let model = PurchaseFormViewModel(ingredient: ingredient)
        #expect(!model.isValid)
        model.quantityText = "100"
        #expect(model.isValid)
    }

    @Test func pricePerUnitComputed() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let model = PurchaseFormViewModel(ingredient: ingredient)
        model.quantityText = "100"
        model.totalPriceText = "25"
        #expect(model.pricePerUnit == 0.25)
    }

    @Test func pricePerUnitZeroWhenQuantityZero() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let model = PurchaseFormViewModel(ingredient: ingredient)
        model.totalPriceText = "25"
        #expect(model.pricePerUnit == 0)
    }

    @Test func saveInsertsNewPurchaseLinkedToIngredient() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let model = PurchaseFormViewModel(ingredient: ingredient)
        model.quantityText = "100"
        model.totalPriceText = "25"
        model.save(context: ctx)
        try ctx.save()
        #expect(ingredient.purchases.count == 1)
        #expect(ingredient.purchases.first?.quantity == 100)
        #expect(ingredient.purchases.first?.remainingAmount == 100)
    }

    @Test func expiryDate_NewPurchase_DefaultsToOneYearFromToday() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let model = PurchaseFormViewModel(ingredient: ingredient)
        let expectedDay = Calendar.current.date(byAdding: .year, value: 1, to: Date())
        let expected = try #require(expectedDay)
        #expect(Calendar.current.isDate(model.expiryDate, inSameDayAs: expected))
    }

    @Test func expiryDate_EditingPurchaseWithExpiry_LoadsStoredDate() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let stored = try #require(Calendar.current.date(byAdding: .month, value: 3, to: Date()))
        let purchase = IngredientPurchase(
            dateOfPurchase: .now,
            quantity: 50,
            totalPrice: 10,
            badge: "",
            journalCode: "",
            expiryDate: stored,
            openingDate: nil
        )
        ctx.insert(purchase)
        ingredient.purchases.append(purchase)
        let model = PurchaseFormViewModel(ingredient: ingredient, purchase: purchase)
        #expect(model.hasExpiryDate)
        #expect(Calendar.current.isDate(model.expiryDate, inSameDayAs: stored))
    }

    @Test func saveUpdatesExistingPurchase() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let purchase = IngredientPurchase(
            dateOfPurchase: .now,
            quantity: 50,
            totalPrice: 10,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        ctx.insert(purchase)
        ingredient.purchases.append(purchase)
        let model = PurchaseFormViewModel(ingredient: ingredient, purchase: purchase)
        model.quantityText = "75"
        model.save(context: ctx)
        #expect(purchase.quantity == 75)
    }
}
