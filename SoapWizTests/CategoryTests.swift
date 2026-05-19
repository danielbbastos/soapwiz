import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("IngredientCategory", .serialized)
@MainActor
struct CategoryTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientBatch.self, IngredientCategory.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test func createCategory() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let category = IngredientCategory(name: "Oils")
        context.insert(category)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<IngredientCategory>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Oils")
    }

    @Test func renamePropagatesImmediately() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let category = IngredientCategory(name: "Oils")
        context.insert(category)
        let ingredient = Ingredient(name: "Olive Oil", category: category)
        context.insert(ingredient)
        try context.save()

        category.name = "Carrier Oils"
        #expect(ingredient.category?.name == "Carrier Oils")
    }

    @Test func deleteAllowedWhenNoIngredients() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let category = IngredientCategory(name: "Empty")
        context.insert(category)
        try context.save()

        #expect(category.ingredients.isEmpty)
        context.delete(category)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<IngredientCategory>())
        #expect(remaining.isEmpty)
    }

    @Test func deleteBlockedWhenIngredientsAssigned() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let category = IngredientCategory(name: "Oils")
        context.insert(category)
        let ingredient = Ingredient(name: "Olive Oil", category: category)
        context.insert(ingredient)
        try context.save()

        #expect(category.ingredients.count == 1)
    }

    @Test func deletingCategoryNullifiesIngredientCategory() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let category = IngredientCategory(name: "Oils")
        context.insert(category)
        let ingredient = Ingredient(name: "Olive Oil", category: category)
        context.insert(ingredient)
        try context.save()

        context.delete(category)
        try context.save()

        #expect(ingredient.category == nil)
    }
}
