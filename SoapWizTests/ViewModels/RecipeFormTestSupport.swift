import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Shared helpers and mocks for the RecipeFormViewModel test suites.
@MainActor
protocol RecipeFormTestHelpers {}

extension RecipeFormTestHelpers {
    func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            Recipe.self, RecipeIngredient.self, RecipeProduct.self,
            Ingredient.self, IngredientPurchase.self, IngredientCategory.self
        ])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return (container, container.mainContext)
    }
    func makeModelWithOils(oils: Double = 1000, waterParts: Double = 1.5) -> RecipeFormViewModel {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil")
        oil.sapValue = 0.2
        model.addOil(oil)
        model.totalOilWeight = oils
        model.oilWeightUnit = "g"
        model.lyePurity = 100
        model.superFat = 0
        model.waterParts = waterParts
        return model
    }
    /// Oils in grams plus one additive entered as a volume, with optional
    /// ingredient density and an optional purchase to give it a cost.
    func makeModelWithVolumeAdditive(
        ctx: ModelContext,
        amount: Double,
        unit: String,
        density: Double?,
        purchase: IngredientPurchase? = nil
    ) -> RecipeFormViewModel {
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        ctx.insert(oil)
        let additive = Ingredient(name: "Glycerin", unit: "ml")
        additive.density = density
        ctx.insert(additive)
        if let purchase {
            purchase.ingredient = additive
            ctx.insert(purchase)
        }

        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.oilWeightUnit = "g"
        model.totalOilWeight = 1000
        model.addOil(oil)
        model.addAdditive(additive)
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: amount, unit: unit)
        return model
    }
    /// 1000 g of oils (SAP 0.2, 0% superfat) → base lye of 200 g at 100% purity.
    func makeNaohModel(purity: Double = 100) -> RecipeFormViewModel {
        let model = RecipeFormViewModel()
        let oil = Ingredient(name: "Coconut Oil", unit: "g")
        oil.sapValue = 0.2
        model.weightUnit = "%"
        model.oilWeightUnit = "g"
        model.totalOilWeight = 1000
        model.lyePurity = purity
        model.superFat = 0
        model.addOil(oil)
        return model
    }
    func makeModelWithOilsAndFragrance(fragranceUnit: String) -> RecipeFormViewModel {
        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.oilWeightUnit = "g"
        model.totalOilWeight = 1000
        model.fragrancePercentage = 3
        model.addOil(Ingredient(name: "Olive Oil"))          // 100% → 1000 g oils
        model.addFragrance(Ingredient(name: "Lavender EO"))
        model.updateFragrance(id: model.fragranceDrafts[0].id, unit: fragranceUnit)
        return model
    }
}

extension IngredientPurchase {
    static func mock(
        quantity: Double = 500,
        totalPrice: Double = 10.0
    ) -> IngredientPurchase {
        IngredientPurchase(
            dateOfPurchase: Date(),
            quantity: quantity,
            totalPrice: totalPrice,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
    }
}
