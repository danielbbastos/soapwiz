import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("CategoryFormViewModel", .serialized)
@MainActor
struct CategoryFormViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientPurchase.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
    }

    @Test func emptyNameInvalid() throws {
        let model = CategoryFormViewModel()
        #expect(!model.isValid(among: []))
    }

    @Test func whitespaceOnlyInvalid() throws {
        let model = CategoryFormViewModel()
        model.name = "   "
        #expect(!model.isValid(among: []))
    }

    @Test func duplicateNameInvalidCaseInsensitive() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = IngredientCategory(name: "Oils")
        ctx.insert(existing)
        let model = CategoryFormViewModel()
        model.name = "oils"
        #expect(model.isDuplicate(among: [existing]))
        #expect(!model.isValid(among: [existing]))
    }

    @Test func editingSelfIsNotDuplicate() throws {
        let existing = IngredientCategory(name: "Oils")
        let model = CategoryFormViewModel(category: existing)
        #expect(!model.isDuplicate(among: [existing]))
        #expect(model.isValid(among: [existing]))
    }

    @Test func saveInsertsNewCategory() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let model = CategoryFormViewModel()
        model.name = "  Oils  "
        model.save(context: ctx)
        try ctx.save()
        let fetched = try ctx.fetch(FetchDescriptor<IngredientCategory>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Oils")
    }

    @Test func saveUpdatesExistingCategory() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = IngredientCategory(name: "Oils")
        ctx.insert(existing)
        let model = CategoryFormViewModel(category: existing)
        model.name = "Carrier Oils"
        model.save(context: ctx)
        #expect(existing.name == "Carrier Oils")
    }

    @Test func save_NewCategory_ReturnsInsertedCategory() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let model = CategoryFormViewModel()
        model.name = "  Oils  "
        let saved = model.save(context: ctx)
        #expect(saved.name == "Oils")
    }

    @Test func save_EditingCategory_ReturnsSameCategory() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = IngredientCategory(name: "Oils")
        ctx.insert(existing)
        let model = CategoryFormViewModel(category: existing)
        model.name = "Carrier Oils"
        let saved = model.save(context: ctx)
        #expect(saved === existing)
    }
}
