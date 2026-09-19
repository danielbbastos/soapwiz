import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// SW-161: the Catherine Failor neutraliser (borax / boric acid) is costed and
/// consumed like any other solid, and its solution counts towards batch weight.
/// Reference figures share the LightCalc model in `SoapMethodTests`: avocado oil
/// 1000 g, dual lye 90% KOH / 10% NaOH at 100% purity, 5% super fat, 2:1 water,
/// boric-acid neutraliser → 14.29 g solid + 57.14 g water.
@Suite("CFM neutraliser cost & consumption", .serialized)
@MainActor
struct CFMNeutralizerCostTests: BatchProductionTestHelpers {

    private func makeLiquidModel(weight: Double = 1000) -> RecipeFormViewModel {
        let oil = Ingredient(name: "Avocado Oil", unit: "g")
        oil.sapValue = 0.132
        oil.kohSapValue = 0.186
        let model = RecipeFormViewModel()
        model.weightUnit = "g"
        model.useHybrid = true
        model.kohPercentage = 90
        model.naohPercentage = 10
        model.kohPurity = 100
        model.naohPurity = 100
        model.superFat = 5
        model.waterParts = 2
        model.addOil(oil)
        model.oilDrafts[0].amount = weight
        model.useCFM = true
        model.cfmNeutralizer = .boricAcid
        return model
    }

    private func isClose(_ actual: Double?, _ expected: Double, tol: Double = 0.02) -> Bool {
        guard let actual else { return false }
        return abs(actual - expected) < tol
    }

    /// A boric-acid ingredient priced at `pricePerUnit` per gram via a single
    /// 100 g purchase.
    private func boricAcid(pricePerUnit: Double) -> Ingredient {
        let boric = Ingredient(name: "Boric Acid", unit: "g")
        let purchase = IngredientPurchase(
            dateOfPurchase: .now, quantity: 100, totalPrice: pricePerUnit * 100,
            badge: "", journalCode: "", expiryDate: nil, openingDate: nil
        )
        purchase.ingredient = boric
        return boric
    }

    private func additivesCategory() -> IngredientCategory {
        IngredientCategory(name: IngredientCategory.Name.additives)
    }

    // MARK: - Cost breakdown

    @Test func costBreakdown_ResolvedNeutralizer_CostsTheSolidUnderAdditives() {
        let model = makeLiquidModel()
        let boric = boricAcid(pricePerUnit: 0.05)
        model.neutralizerIngredient = boric

        let row = model.wholeBatchBreakdown.additives.first {
            $0.ingredient.persistentModelID == boric.persistentModelID
        }
        #expect(row != nil)
        #expect(isClose(row?.ingredientAmount, 14.29))
        #expect(isClose(row?.cost, 14.29 * 0.05, tol: 0.01))
    }

    @Test func costBreakdown_NoNeutralizer_NoSolidRow() {
        let model = makeLiquidModel()
        // Dose is still shown in the amounts table, but nothing is costed.
        #expect(model.wholeBatchBreakdown.additives.isEmpty)
        #expect(model.calculatedAmountRows?.contains { $0.label.contains("Boric Acid") } == true)
    }

    @Test func costBreakdown_CFMOff_NoSolidRow() {
        let model = makeLiquidModel()
        model.useCFM = false
        model.neutralizerIngredient = boricAcid(pricePerUnit: 0.05)
        #expect(model.wholeBatchBreakdown.additives.isEmpty)
    }

    // MARK: - Batch weight

    @Test func batchTotalWeight_IncludesFullSolution_WhenResolved() throws {
        let model = makeLiquidModel()
        model.neutralizerIngredient = boricAcid(pricePerUnit: 0.05)

        let solid = try #require(model.lyeCalculator.cfmNeutralizerSolidWeight)
        let water = try #require(model.lyeCalculator.cfmNeutralizerWaterWeight)
        let lye = try #require(model.calculatedLyeAmount)
        let recipeWater = try #require(model.calculatedWaterAmount)
        #expect(isClose(model.batchTotalWeight, 1000 + lye + recipeWater + solid + water, tol: 0.1))
    }

    @Test func batchTotalWeight_IncludesFullSolution_EvenWhenUnresolved() throws {
        let model = makeLiquidModel() // no neutraliser ingredient resolved
        let solid = try #require(model.lyeCalculator.cfmNeutralizerSolidWeight)
        let water = try #require(model.lyeCalculator.cfmNeutralizerWaterWeight)
        let lye = try #require(model.calculatedLyeAmount)
        let recipeWater = try #require(model.calculatedWaterAmount)
        // The mass is in the pot regardless of whether it is costed — the weight
        // is the same whether or not an ingredient was resolved.
        #expect(isClose(model.batchTotalWeight, 1000 + lye + recipeWater + solid + water, tol: 0.1))
    }

    // MARK: - Default resolution & switching

    @Test func resolveDefault_FillsBlank_MatchingBySlug() {
        let model = makeLiquidModel()
        let boric = Ingredient(name: "Boric Acid", unit: "g")
        boric.librarySlug = "boric-acid"
        boric.category = additivesCategory()
        let borax = Ingredient(name: "Borax", unit: "g")
        borax.librarySlug = "borax"
        borax.category = additivesCategory()

        model.resolveDefaultNeutralizerIngredient(from: [borax, boric])
        #expect(model.neutralizerIngredient?.librarySlug == "boric-acid")
    }

    @Test func resolveDefault_DoesNotOverrideExistingChoice() {
        let model = makeLiquidModel()
        let chosen = boricAcid(pricePerUnit: 0.05)
        model.neutralizerIngredient = chosen

        let borax = Ingredient(name: "Borax", unit: "g")
        borax.librarySlug = "borax"
        borax.category = additivesCategory()
        model.cfmNeutralizer = .borax
        model.resolveDefaultNeutralizerIngredient(from: [borax])
        #expect(model.neutralizerIngredient?.persistentModelID == chosen.persistentModelID)
    }

    @Test func setNeutralizer_MovesToNewDefault_WhenStillDefault() {
        let model = makeLiquidModel()
        let boric = Ingredient(name: "Boric Acid", unit: "g")
        boric.librarySlug = "boric-acid"
        boric.category = additivesCategory()
        let borax = Ingredient(name: "Borax", unit: "g")
        borax.librarySlug = "borax"
        borax.category = additivesCategory()
        model.neutralizerIngredient = boric

        model.setCFMNeutralizer(.borax, from: [boric, borax])
        #expect(model.cfmNeutralizer == .borax)
        #expect(model.neutralizerIngredient?.librarySlug == "borax")
    }

    @Test func setNeutralizer_KeepsManualOverride() {
        let model = makeLiquidModel()
        let custom = Ingredient(name: "My Neutraliser", unit: "g") // no library slug
        custom.category = additivesCategory()
        let borax = Ingredient(name: "Borax", unit: "g")
        borax.librarySlug = "borax"
        borax.category = additivesCategory()
        model.neutralizerIngredient = custom

        model.setCFMNeutralizer(.borax, from: [custom, borax])
        #expect(model.neutralizerIngredient?.persistentModelID == custom.persistentModelID)
    }

    // MARK: - Unit system for rule-of-thumb copy

    @Test func usesImperialUnits_FollowsDisplayUnit() {
        let model = makeLiquidModel()
        for unit in ["g", "kg"] {
            model.weightUnit = unit
            #expect(!model.usesImperialUnits, "\(unit) is metric")
        }
        for unit in ["oz", "lb"] {
            model.weightUnit = unit
            #expect(model.usesImperialUnits, "\(unit) is imperial")
        }
    }

    @Test func usesImperialUnits_PercentageMode_FollowsOilWeightUnit() {
        let model = makeLiquidModel()
        model.weightUnit = "%"
        model.oilWeightUnit = "oz"
        #expect(model.usesImperialUnits)
        model.oilWeightUnit = "g"
        #expect(!model.usesImperialUnits)
    }

    // MARK: - Batch consumption

    /// The ingredients a liquid-soap batch draws from.
    private struct LiquidSoapStock {
        let oil: Ingredient
        let naoh: Ingredient
        let koh: Ingredient
    }

    /// Stocked oil and both lyes for a liquid-soap batch: oil sap NaOH 0.132 /
    /// KOH 0.186, everything bought 10 days ago.
    private func seedLiquidSoapStock(_ ctx: ModelContext) -> LiquidSoapStock {
        let oil = Ingredient(name: "Avocado Oil", unit: "g")
        oil.sapValue = 0.132
        oil.kohSapValue = 0.186
        ctx.insert(oil)
        purchase(ctx, for: oil, quantity: 5000, totalPrice: 50, daysAgo: 10)

        let naoh = Ingredient(name: "Sodium Hydroxide", unit: "g")
        ctx.insert(naoh)
        purchase(ctx, for: naoh, quantity: 1000, totalPrice: 10, daysAgo: 10)

        let koh = Ingredient(name: "Potassium Hydroxide", unit: "g")
        ctx.insert(koh)
        purchase(ctx, for: koh, quantity: 1000, totalPrice: 20, daysAgo: 10)
        return LiquidSoapStock(oil: oil, naoh: naoh, koh: koh)
    }

    private func makeCFMRecipe(
        _ ctx: ModelContext, oil: Ingredient, naoh: Ingredient, koh: Ingredient,
        neutralizer: Ingredient?, oilWeight: Double = 1000
    ) -> Recipe {
        let recipe = Recipe(name: "Liquid Soap")
        recipe.weightUnit = "g"
        recipe.useHybrid = true
        recipe.kohPercentage = 90
        recipe.naohPercentage = 10
        recipe.kohPurity = 100
        recipe.naohPurity = 100
        recipe.superFat = 5
        recipe.waterParts = 2
        recipe.useCFM = true
        recipe.cfmNeutralizer = CFMNeutralizer.boricAcid.rawValue
        recipe.lyeIngredient = naoh
        recipe.kohLyeIngredient = koh
        recipe.neutralizerIngredient = neutralizer
        ctx.insert(recipe)
        let oilLine = RecipeIngredient(ingredient: oil, percentage: oilWeight, role: .oil)
        oilLine.recipe = recipe
        ctx.insert(oilLine)
        return recipe
    }

    @Test func batch_DeductsNeutralizerFIFO_AndRecordsLineItem() throws {
        let (container, ctx) = try makeContext()
        _ = container

        let stock = seedLiquidSoapStock(ctx)

        let boric = Ingredient(name: "Boric Acid", unit: "g")
        ctx.insert(boric)
        let boricPurchase = purchase(ctx, for: boric, quantity: 100, totalPrice: 5, daysAgo: 10) // 0.05/g

        let recipe = makeCFMRecipe(ctx, oil: stock.oil, naoh: stock.naoh, koh: stock.koh, neutralizer: boric)
        try ctx.save()

        let model = BatchProductionViewModel(
            recipe: recipe, lyeCandidates: [stock.naoh, stock.koh], neutralizerCandidates: [boric]
        )

        let req = try #require(model.requirements.first {
            $0.ingredient.persistentModelID == boric.persistentModelID
        })
        #expect(isClose(req.required, 14.29))

        let batch = try #require(model.create(context: ctx))
        #expect(isClose(boricPurchase.remainingAmount, 100 - 14.29))

        let line = try #require(batch.lineItems.first { $0.ingredientName == "Boric Acid" })
        #expect(isClose(line.amountConsumed, 14.29))
        #expect(isClose(line.cost, 14.29 * 0.05, tol: 0.01))
    }

    @Test func batch_NoNeutralizer_StillCreatable_NoBoricLine() throws {
        let (container, ctx) = try makeContext()
        _ = container

        let stock = seedLiquidSoapStock(ctx)

        let recipe = makeCFMRecipe(ctx, oil: stock.oil, naoh: stock.naoh, koh: stock.koh, neutralizer: nil)
        try ctx.save()

        let model = BatchProductionViewModel(
            recipe: recipe, lyeCandidates: [stock.naoh, stock.koh], neutralizerCandidates: []
        )

        #expect(!model.requirements.contains { $0.ingredient.name == "Boric Acid" })
        let batch = try #require(model.create(context: ctx))
        #expect(!batch.lineItems.contains { $0.ingredientName == "Boric Acid" })
    }
}
