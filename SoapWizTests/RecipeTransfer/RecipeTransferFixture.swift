import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Container, context and a builder for fully-populated recipes.
///
/// Held together so a suite can own one for the life of each test: a container
/// that goes out of scope takes its models with it, and every `Recipe` here has
/// to outlive the call that created it.
@MainActor
struct RecipeTransferFixture {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        let schema = Schema([
            Recipe.self, RecipeIngredient.self, RecipeProduct.self, RecipeCollection.self,
            Ingredient.self, IngredientPurchase.self, IngredientCategory.self
        ])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        self.container = container
        self.context = container.mainContext
    }

    // MARK: - Building blocks

    @discardableResult
    func oil(
        _ name: String,
        sap: Double? = 0.1345,
        kohSap: Double? = 0.1885,
        density: Double? = 0.91,
        profile: FattyAcidProfile? = .mock,
        unit: String = "g"
    ) -> Ingredient {
        let ingredient = Ingredient(name: name, unit: unit)
        ingredient.sapValue = sap
        ingredient.kohSapValue = kohSap
        ingredient.density = density
        ingredient.fattyAcidProfile = profile
        context.insert(ingredient)
        return ingredient
    }

    func collection(_ name: String, color: String = "") -> RecipeCollection {
        let collection = RecipeCollection(name: name, colorName: color)
        context.insert(collection)
        return collection
    }

    /// A recipe with every field set to something distinguishable from its
    /// default, so a field the encoder forgets shows up as a mismatch rather
    /// than coincidentally matching the schema default on the way back.
    func recipe(named name: String = "Round Trip Bar") -> Recipe {
        let recipe = Recipe(name: name, desc: "Every field set to something unusual.")
        context.insert(recipe)

        recipe.recipeKind = RecipeKind.soap.rawValue
        recipe.weightUnit = "%"
        recipe.totalOilWeight = 1234.5
        recipe.oilWeightUnit = "oz"
        recipe.lyeType = "KOH"
        recipe.lyePurity = 91.5
        recipe.waterParts = 2.25
        recipe.superFat = 7.5
        recipe.fragrancePercentage = 4.25
        recipe.fragranceUnit = FragranceUnit.percentOfFragrances.rawValue
        recipe.useHybrid = true
        recipe.kohPercentage = 73
        recipe.naohPercentage = 27
        recipe.kohPurity = 88.5
        recipe.naohPurity = 97.25
        recipe.isCreamSoap = true
        recipe.useCFM = true
        recipe.cfmNeutralizer = CFMNeutralizer.borax.rawValue
        return recipe
    }

    func addOil(_ ingredient: Ingredient, percentage: Double, to recipe: Recipe) {
        let line = RecipeIngredient(ingredient: ingredient, percentage: percentage, role: .oil)
        line.recipe = recipe
        context.insert(line)
    }

    func addAmountRow(
        _ ingredient: Ingredient,
        role: RecipeIngredientRole,
        amount: Double,
        unit: String,
        to recipe: Recipe
    ) {
        let line = RecipeIngredient(ingredient: ingredient, percentage: 0, role: role)
        line.additiveAmount = amount
        line.additiveUnit = unit
        line.recipe = recipe
        context.insert(line)
    }

    func addProduct(size: Double, unitSymbol: String, to recipe: Recipe) {
        let product = RecipeProduct(size: size, unitSymbol: unitSymbol)
        product.recipe = recipe
        context.insert(product)
    }

    /// The recipe every round-trip test starts from: three oils, an additive, a
    /// fragrance, two products and two collections.
    func populatedRecipe(named name: String = "Round Trip Bar") -> Recipe {
        let recipe = self.recipe(named: name)
        addOil(oil("Olive Oil", sap: 0.1345), percentage: 55, to: recipe)
        addOil(oil("Coconut Oil", sap: 0.1783), percentage: 30, to: recipe)
        addOil(oil("Castor Oil", sap: 0.1286), percentage: 15, to: recipe)
        addAmountRow(
            oil("Sodium Lactate", sap: nil, kohSap: nil, density: nil, profile: nil),
            role: .additive,
            amount: 2.5,
            unit: "% of oils",
            to: recipe
        )
        addAmountRow(
            oil("Lavender Essential Oil", sap: nil, kohSap: nil, density: 0.89, profile: nil),
            role: .fragrance,
            amount: 60,
            unit: FragranceUnit.percentOfFragrances.rawValue,
            to: recipe
        )
        addProduct(size: 100, unitSymbol: "g", to: recipe)
        addProduct(size: 1, unitSymbol: ProductUnit.partsOfBatch.rawValue, to: recipe)
        recipe.collections = [collection("Christmas"), collection("Gifts")]
        context.processPendingChanges()
        return recipe
    }
}

extension FattyAcidProfile {
    /// A profile with every acid distinct, so a field dropped or transposed in
    /// encoding can't hide behind a matching neighbour.
    static var mock: FattyAcidProfile {
        var profile = FattyAcidProfile()
        profile.lauric = 1
        profile.myristic = 2
        profile.palmitic = 3
        profile.stearic = 4
        profile.oleic = 5
        profile.linoleic = 6
        profile.linolenic = 7
        profile.ricinoleic = 8
        return profile
    }
}
