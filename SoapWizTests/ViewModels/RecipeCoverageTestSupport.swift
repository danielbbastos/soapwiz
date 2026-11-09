import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// A CFM recipe with its lyes and a boric acid neutraliser, as
/// `RecipeCoverageTestHelpers.neutralizerSetup` builds it.
struct NeutralizerSetup {
    let recipe: Recipe
    let boric: Ingredient
    let lyes: [Ingredient]
}

/// Shared helpers for the RecipeCoverage test suites.
@MainActor
protocol RecipeCoverageTestHelpers: BatchProductionTestHelpers {}

extension RecipeCoverageTestHelpers {

    func stock(_ ctx: ModelContext) throws -> StockLevels {
        StockLevels(try ctx.fetch(FetchDescriptor<IngredientPurchase>()))
    }

    func coverage(
        _ recipe: Recipe,
        _ ctx: ModelContext,
        lyes: [Ingredient] = [],
        neutralizers: [Ingredient] = [],
        calculator: RecipeCoverage? = nil
    ) throws -> RecipeCoverage.Coverage? {
        (calculator ?? RecipeCoverage()).coverage(
            for: recipe,
            stock: try stock(ctx),
            lyeCandidates: lyes,
            neutralizerCandidates: neutralizers,
            tracksInventory: true
        )
    }

    /// Asserts `result` is what Create Batch says: no shortage at its own
    /// count, one at the next, and the same shortfalls for a single batch.
    func expectAgreement(
        _ result: RecipeCoverage.Coverage,
        recipe: Recipe,
        lyes: [Ingredient] = [],
        neutralizers: [Ingredient] = []
    ) {
        let model = BatchProductionViewModel(
            recipe: recipe,
            lyeCandidates: lyes,
            neutralizerCandidates: neutralizers,
            tracksInventory: true
        )
        if result.batches > 0 {
            model.batchCount = result.batches
            #expect(model.shortages.isEmpty)
        }
        model.batchCount = result.batches + 1
        #expect(!model.shortages.isEmpty)

        model.batchCount = 1
        let expected = model.shortages
        #expect(result.shortages.map(\.id) == expected.map(\.id))
        for (shortage, requirement) in zip(result.shortages, expected) {
            #expect(abs(shortage.shortfall - requirement.shortfall) < 1e-9)
            #expect(shortage.unit == requirement.unit)
        }
    }

    func lyeIngredients(_ ctx: ModelContext) -> (naoh: Ingredient, koh: Ingredient) {
        let lyes = IngredientCategory(name: IngredientCategory.Name.lyes)
        ctx.insert(lyes)
        let naoh = Ingredient(name: "Sodium Hydroxide", category: lyes, unit: "g")
        let koh = Ingredient(name: "Potassium Hydroxide", category: lyes, unit: "g")
        ctx.insert(naoh)
        ctx.insert(koh)
        purchase(ctx, for: naoh, quantity: 1000, totalPrice: 10, daysAgo: 5)
        purchase(ctx, for: koh, quantity: 1000, totalPrice: 10, daysAgo: 5)
        return (naoh, koh)
    }

    func oil(_ ctx: ModelContext, unit: String = "g", stocked: Double) -> Ingredient {
        let oil = Ingredient(name: "Olive Oil", unit: unit)
        oil.sapValue = 0.2
        oil.kohSapValue = 0.28
        ctx.insert(oil)
        if stocked > 0 {
            purchase(ctx, for: oil, quantity: stocked, totalPrice: 10, daysAgo: 5)
        }
        return oil
    }

    func neutralizerSetup(_ ctx: ModelContext, boricStock: Double) -> NeutralizerSetup {
        let lye = lyeIngredients(ctx)
        let additives = IngredientCategory(name: IngredientCategory.Name.additives)
        ctx.insert(additives)
        let boric = Ingredient(name: "Boric Acid", category: additives, unit: "g")
        boric.librarySlug = CFMNeutralizer.boricAcid.librarySlug
        ctx.insert(boric)
        purchase(ctx, for: boric, quantity: boricStock, totalPrice: 5, daysAgo: 2)
        let recipe = makeRecipe(ctx, oil: oil(ctx, stocked: 50000), oilWeight: 1000)
        recipe.lyeType = "KOH"
        recipe.useCFM = true
        recipe.cfmNeutralizer = CFMNeutralizer.boricAcid.rawValue
        return NeutralizerSetup(recipe: recipe, boric: boric, lyes: [lye.naoh, lye.koh])
    }
}
