import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The inventory's fetch prefetches relationships so a refetch stays cheap
/// during an iCloud import (SW-219). Prefetching must not change what it
/// returns.
@Suite("Ingredient list fetch")
@MainActor
struct IngredientListFetchTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    @Test func listDescriptor_EmptyStore_ReturnsNothing() throws {
        let (container, context) = try makeContext()
        _ = container

        let fetched = try context.fetch(Ingredient.listDescriptor)

        #expect(fetched.isEmpty)
    }

    @Test func listDescriptor_SortsByName() throws {
        let (container, context) = try makeContext()
        _ = container
        for name in ["Shea Butter", "Coconut Oil", "Olive Oil"] {
            context.insert(Ingredient(name: name, unit: "g"))
        }
        try context.save()

        let fetched = try context.fetch(Ingredient.listDescriptor)

        #expect(fetched.map(\.name) == ["Coconut Oil", "Olive Oil", "Shea Butter"])
    }

    @Test func listDescriptor_KeepsPurchasesAndRecipeLines() throws {
        let (container, context) = try makeContext()
        _ = container
        let olive = Ingredient(name: "Olive Oil", unit: "g")
        let recipe = Recipe(name: "Bastille")
        context.insert(olive)
        context.insert(recipe)
        for quantity in [300.0, 200.0] {
            let purchase = IngredientPurchase.mock(quantity: quantity)
            purchase.ingredient = olive
            context.insert(purchase)
        }
        let line = RecipeIngredient(ingredient: olive, percentage: 100, role: .oil)
        line.recipe = recipe
        context.insert(line)
        try context.save()

        let fetched = try #require(try context.fetch(Ingredient.listDescriptor).first)

        #expect(fetched.purchases.count == 2)
        #expect(fetched.totalRemaining == 500)
        #expect(fetched.isUsedInRecipes)
    }
}

extension IngredientPurchase {
    fileprivate static func mock(quantity: Double) -> IngredientPurchase {
        IngredientPurchase(
            dateOfPurchase: .now, quantity: quantity, totalPrice: 5,
            badge: "", journalCode: "", expiryDate: nil, openingDate: nil
        )
    }
}
