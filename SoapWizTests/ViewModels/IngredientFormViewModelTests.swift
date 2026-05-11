import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("IngredientFormViewModel")
@MainActor
struct IngredientFormViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientBatch.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    @Test func requiresNameAndUnit() {
        let model = IngredientFormViewModel()
        #expect(!model.isValid)
        model.name = "Olive Oil"
        #expect(!model.isValid)
        model.unit = "g"
        #expect(model.isValid)
    }

    @Test func whitespaceOnlyInvalid() {
        let model = IngredientFormViewModel()
        model.name = "   "
        model.unit = "   "
        #expect(!model.isValid)
    }

    @Test func saveInsertsTrimmedFields() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let cat = IngredientCategory(name: "Oils")
        ctx.insert(cat)
        let model = IngredientFormViewModel()
        model.name = "  Olive Oil  "
        model.unit = "  g  "
        model.selectedCategory = cat
        model.save(context: ctx)
        try ctx.save()
        let fetched = try ctx.fetch(FetchDescriptor<Ingredient>())
        #expect(fetched.first?.name == "Olive Oil")
        #expect(fetched.first?.unit == "g")
        #expect(fetched.first?.category === cat)
    }

    @Test func saveUpdatesExisting() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(existing)
        let model = IngredientFormViewModel(ingredient: existing)
        model.name = "Coconut Oil"
        model.save(context: ctx)
        #expect(existing.name == "Coconut Oil")
    }
}
