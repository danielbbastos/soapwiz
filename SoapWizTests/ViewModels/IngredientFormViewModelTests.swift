import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("IngredientFormViewModel", .serialized)
@MainActor
struct IngredientFormViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientBatch.self, IngredientCategory.self, QuantityUnit.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    @Test func emptyNameInvalid() {
        let model = IngredientFormViewModel()
        #expect(!model.isValid)
    }

    @Test func requiresNameAndUnit() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let gram = QuantityUnit(name: "Gram", symbol: "g")
        ctx.insert(gram)

        let model = IngredientFormViewModel()
        #expect(!model.isValid)
        model.name = "Olive Oil"
        #expect(!model.isValid)
        model.selectedUnit = gram
        #expect(model.isValid)
    }

    @Test func whitespaceOnlyNameInvalid() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let gram = QuantityUnit(name: "Gram", symbol: "g")
        ctx.insert(gram)

        let model = IngredientFormViewModel()
        model.name = "   "
        model.selectedUnit = gram
        #expect(!model.isValid)
    }

    @Test func saveInsertsTrimmedFields() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let cat = IngredientCategory(name: "Oils")
        ctx.insert(cat)
        let gram = QuantityUnit(name: "Gram", symbol: "g")
        ctx.insert(gram)

        let model = IngredientFormViewModel()
        model.name = "  Olive Oil  "
        model.selectedUnit = gram
        model.selectedCategory = cat
        let returned = model.save(context: ctx)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Ingredient>())
        #expect(fetched.first?.name == "Olive Oil")
        #expect(fetched.first?.unit === gram)
        #expect(fetched.first?.category === cat)
        #expect(returned === fetched.first)
    }

    @Test func saveUpdatesExisting() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = Ingredient(name: "Olive Oil")
        ctx.insert(existing)

        let model = IngredientFormViewModel(ingredient: existing)
        model.name = "Coconut Oil"
        let returned = model.save(context: ctx)
        #expect(existing.name == "Coconut Oil")
        #expect(returned == nil)
    }

    @Test func saveStoresThreshold() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let gram = QuantityUnit(name: "Gram", symbol: "g")
        ctx.insert(gram)

        let model = IngredientFormViewModel()
        model.name = "Olive Oil"
        model.selectedUnit = gram
        model.lowStockThreshold = "100"
        let ingredient = model.save(context: ctx)
        #expect(ingredient?.lowStockThreshold == 100)
    }

    @Test func saveClearsThresholdWhenEmpty() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = Ingredient(name: "Olive Oil")
        existing.lowStockThreshold = 50
        ctx.insert(existing)

        let model = IngredientFormViewModel(ingredient: existing)
        model.lowStockThreshold = ""
        model.save(context: ctx)
        #expect(existing.lowStockThreshold == nil)
    }

    @Test func populatesThresholdWhenEditing() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = Ingredient(name: "Olive Oil")
        existing.lowStockThreshold = 75.5
        ctx.insert(existing)

        let model = IngredientFormViewModel(ingredient: existing)
        let parsed = Double(model.lowStockThreshold.replacingOccurrences(of: ",", with: "."))
        #expect(parsed == 75.5)
    }
}
