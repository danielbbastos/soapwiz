import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("BatchFormViewModel")
@MainActor
struct BatchFormViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientBatch.self, IngredientCategory.self, QuantityUnit.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    @Test func quantityRequiredForValid() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let model = BatchFormViewModel(ingredient: ingredient)
        #expect(!model.isValid)
        model.quantityText = "100"
        #expect(model.isValid)
    }

    @Test func pricePerUnitComputed() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let model = BatchFormViewModel(ingredient: ingredient)
        model.quantityText = "100"
        model.totalPriceText = "25"
        #expect(model.pricePerUnit == 0.25)
    }

    @Test func pricePerUnitZeroWhenQuantityZero() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let model = BatchFormViewModel(ingredient: ingredient)
        model.totalPriceText = "25"
        #expect(model.pricePerUnit == 0)
    }

    @Test func saveInsertsNewBatchLinkedToIngredient() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let model = BatchFormViewModel(ingredient: ingredient)
        model.quantityText = "100"
        model.totalPriceText = "25"
        model.save(context: ctx)
        try ctx.save()
        #expect(ingredient.batches.count == 1)
        #expect(ingredient.batches.first?.quantity == 100)
        #expect(ingredient.batches.first?.remainingAmount == 100)
    }

    @Test func saveUpdatesExistingBatch() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Olive Oil")
        ctx.insert(ingredient)
        let batch = IngredientBatch(
            dateOfPurchase: .now,
            quantity: 50,
            totalPrice: 10,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        ctx.insert(batch)
        ingredient.batches.append(batch)
        let model = BatchFormViewModel(ingredient: ingredient, batch: batch)
        model.quantityText = "75"
        model.save(context: ctx)
        #expect(batch.quantity == 75)
    }
}
