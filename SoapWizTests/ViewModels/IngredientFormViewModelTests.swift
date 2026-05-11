import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("IngredientFormViewModel")
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
        model.save(context: ctx)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Ingredient>())
        #expect(fetched.first?.name == "Olive Oil")
        #expect(fetched.first?.unit === gram)
        #expect(fetched.first?.category === cat)
    }

    @Test func saveUpdatesExisting() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = Ingredient(name: "Olive Oil")
        ctx.insert(existing)

        let model = IngredientFormViewModel(ingredient: existing)
        model.name = "Coconut Oil"
        model.save(context: ctx)
        #expect(existing.name == "Coconut Oil")
    }
}
