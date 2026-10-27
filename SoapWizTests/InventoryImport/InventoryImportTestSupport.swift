import Foundation
import SwiftData
@testable import SoapWiz

@MainActor
enum InventoryImportTestSupport {
    static func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    @discardableResult
    static func insertIngredient(
        _ name: String,
        unit: IngredientUnit = .grams,
        density: Double? = nil,
        slug: String = "",
        code: String = "",
        isHidden: Bool = false,
        in context: ModelContext
    ) -> Ingredient {
        let ingredient = Ingredient(name: name, unit: unit.rawValue)
        ingredient.density = density
        ingredient.librarySlug = slug
        ingredient.code = code
        ingredient.isHidden = isHidden
        context.insert(ingredient)
        return ingredient
    }

    static func plan(
        _ rows: [InventoryImportRow],
        inventory: [Ingredient]
    ) -> InventoryImportPlan {
        InventoryImportMatcher.plan(for: rows, inventory: inventory)
    }
}
