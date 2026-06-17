import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Shared helpers for the BatchProductionViewModelTests test suites.
@MainActor
protocol BatchProductionTestHelpers {}

extension BatchProductionTestHelpers {
    func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            Recipe.self, RecipeIngredient.self, RecipeProduct.self,
            Ingredient.self, IngredientPurchase.self, IngredientCategory.self,
            Batch.self, BatchLineItem.self
        ])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return (container, container.mainContext)
    }
    /// A recipe measured directly in grams with a single oil of `oilWeight` g, no
    /// lye ingredient (so only the oil appears as a requirement) — gives a
    /// predictable required amount of exactly `oilWeight`.
    func makeRecipe(_ ctx: ModelContext, oil: Ingredient, oilWeight: Double) -> Recipe {
        let recipe = Recipe(name: "Test Soap")
        recipe.weightUnit = "g"
        recipe.lyePurity = 100
        recipe.superFat = 0
        ctx.insert(recipe)
        let recipeIngredient = RecipeIngredient(ingredient: oil, percentage: oilWeight, role: .oil)
        recipeIngredient.recipe = recipe
        ctx.insert(recipeIngredient)
        return recipe
    }
    @discardableResult
    func purchase(
        _ ctx: ModelContext, for ingredient: Ingredient,
        quantity: Double, totalPrice: Double, daysAgo: Int, badge: String = ""
    ) -> IngredientPurchase {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        let purchase = IngredientPurchase(
            dateOfPurchase: date, quantity: quantity, totalPrice: totalPrice,
            badge: badge, journalCode: "", expiryDate: nil, openingDate: nil
        )
        purchase.ingredient = ingredient
        ctx.insert(purchase)
        return purchase
    }
}
