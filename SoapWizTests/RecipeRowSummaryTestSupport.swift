import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Shared container and fixtures for the `RecipeRowSummary` suites.
@MainActor
protocol RecipeRowSummaryTestHelpers {}

extension RecipeRowSummaryTestHelpers {
    func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }
}

@MainActor
extension Recipe {
    /// Defaults to percentage mode. `Recipe.weightUnit` itself defaults to "g",
    /// which is absolute mode — so a fixture that does not say puts every oil
    /// amount in grams while the assertion reads it as a percentage. Tests that
    /// want absolute mode pass it explicitly.
    static func mock(
        name: String = "Test Recipe",
        desc: String = "",
        weightUnit: String = "%",
        in ctx: ModelContext
    ) -> Recipe {
        let recipe = Recipe(name: name, desc: desc)
        recipe.weightUnit = weightUnit
        ctx.insert(recipe)
        return recipe
    }

    func addOils(_ oils: [(String, Double)], in ctx: ModelContext) {
        for (name, percentage) in oils {
            addLine(name: name, percentage: percentage, role: .oil, in: ctx)
        }
    }

    func addLine(
        name: String,
        percentage: Double,
        role: RecipeIngredientRole,
        in ctx: ModelContext
    ) {
        let ingredient = Ingredient(name: name, unit: "g")
        ctx.insert(ingredient)
        let line = RecipeIngredient(ingredient: ingredient, percentage: percentage, role: role)
        ctx.insert(line)
        line.recipe = self
    }
}
