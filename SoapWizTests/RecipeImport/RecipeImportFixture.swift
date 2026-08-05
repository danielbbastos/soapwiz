import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Container, context and a small inventory, held together so a suite can own
/// one for the life of each test. A container that goes out of scope takes its
/// models with it, and every `Ingredient` here has to outlive the call that
/// created it.
@MainActor
struct RecipeImportFixture {
    let container: ModelContainer
    let context: ModelContext
    let inventory: [Ingredient]

    init() throws {
        let schema = Schema([
            Recipe.self, RecipeIngredient.self, RecipeProduct.self,
            Ingredient.self, IngredientPurchase.self, IngredientCategory.self
        ])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        let context = container.mainContext

        let oils = IngredientCategory(name: IngredientCategory.Name.oils)
        let fragrances = IngredientCategory(name: IngredientCategory.Name.fragrances)
        context.insert(oils)
        context.insert(fragrances)

        func makeOil(_ name: String, sap: Double) -> Ingredient {
            let oil = Ingredient(name: name, category: oils, unit: "g")
            oil.sapValue = sap
            context.insert(oil)
            return oil
        }

        let lavender = Ingredient(name: "Lavender Essential Oil", category: fragrances, unit: "g")
        context.insert(lavender)

        self.container = container
        self.context = context
        self.inventory = [
            makeOil("Olive Oil", sap: 0.1345),
            makeOil("Coconut Oil", sap: 0.1783),
            makeOil("Castor Oil", sap: 0.1286),
            lavender
        ]
    }

    func insert(_ name: String, unit: String = "g") -> Ingredient {
        let ingredient = Ingredient(name: name, unit: unit)
        context.insert(ingredient)
        return ingredient
    }

    /// Reconciles a draft against the inventory and applies it to a fresh form.
    func apply(_ draft: RecipeImportDraft, inventory extra: [Ingredient] = []) -> RecipeFormViewModel {
        let rows = RecipeIngredientReconciler.reconcile(draft, against: inventory + extra)
        let model = RecipeFormViewModel()
        model.applyImport(PreparedRecipeImport(draft: draft, rows: rows))
        return model
    }
}
