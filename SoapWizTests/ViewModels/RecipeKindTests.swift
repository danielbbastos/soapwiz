import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Recipe kind – model and form", .serialized)
@MainActor
struct RecipeKindFormTests: RecipeFormTestHelpers {

    // MARK: - Defaults

    @Test func recipeKind_NewRecipe_IsSoap() {
        let recipe = Recipe(name: "Castile")

        #expect(RecipeKind.resolve(recipe.recipeKind) == .soap)
    }

    @Test func recipeKind_NewForm_IsSoap() {
        let model = RecipeFormViewModel()

        #expect(model.recipeKind == .soap)
        #expect(model.isNonSoapProduct == false)
        #expect(model.makesSoap)
    }

    @Test func resolve_UnknownRawValue_FallsBackToSoap() {
        #expect(RecipeKind.resolve("candle-ish") == .soap)
    }

    // MARK: - Toggle

    @Test func isNonSoapProduct_TurnedOn_SetsGeneralKind() {
        let model = RecipeFormViewModel()

        model.isNonSoapProduct = true

        #expect(model.recipeKind == .general)
        #expect(model.makesSoap == false)
    }

    @Test func isNonSoapProduct_TurnedOffAgain_ReturnsToSoap() {
        let model = RecipeFormViewModel()
        model.isNonSoapProduct = true

        model.isNonSoapProduct = false

        #expect(model.recipeKind == .soap)
    }

    @Test func baseWeightLabel_FollowsKind() {
        let model = RecipeFormViewModel()

        #expect(model.baseWeightLabel == "Total oil weight")

        model.isNonSoapProduct = true

        #expect(model.baseWeightLabel == "Total weight")
    }

    // MARK: - Round-trip

    @Test func saveAndLoad_GeneralRecipe_PreservesKind() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()
        model.name = "Beeswax Candle"
        model.isNonSoapProduct = true

        let saved = model.save(context: ctx)
        let reloaded = RecipeFormViewModel()
        reloaded.load(from: saved)

        #expect(saved.recipeKind == RecipeKind.general.rawValue)
        #expect(reloaded.recipeKind == .general)
        #expect(reloaded.isNonSoapProduct)
    }

    @Test func load_RecipeStoredBeforeTheKindExisted_ReadsAsSoap() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe(name: "Old Castile")
        // Stands in for a row migrated in without the attribute set.
        recipe.recipeKind = ""
        ctx.insert(recipe)

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.recipeKind == .soap)
    }

    @Test func switchToGeneralAndBack_PreservesLyeConfiguration() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()
        model.name = "Convertible"
        model.lyeType = "KOH"
        model.lyePurity = 88
        model.waterParts = 2.4
        model.superFat = 8
        model.useHybrid = true
        model.setKOHPercentage(70)
        model.kohPurity = 91
        model.naohPurity = 97
        model.isCreamSoap = true
        model.useCFM = true
        model.cfmNeutralizer = .borax

        model.isNonSoapProduct = true
        let saved = model.save(context: ctx)
        let reloaded = RecipeFormViewModel()
        reloaded.load(from: saved)
        reloaded.isNonSoapProduct = false

        #expect(reloaded.lyeType == "KOH")
        #expect(reloaded.lyePurity == 88)
        #expect(reloaded.waterParts == 2.4)
        #expect(reloaded.superFat == 8)
        #expect(reloaded.useHybrid)
        #expect(reloaded.kohPercentage == 70)
        #expect(reloaded.naohPercentage == 30)
        #expect(reloaded.kohPurity == 91)
        #expect(reloaded.naohPurity == 97)
        #expect(reloaded.isCreamSoap)
        #expect(reloaded.useCFM)
        #expect(reloaded.cfmNeutralizer == .borax)
    }

    // MARK: - Dirty state

    @Test func isDirty_KindToggled_IsTrue() {
        let model = RecipeFormViewModel()
        model.captureSnapshot()

        model.isNonSoapProduct = true

        #expect(model.isDirty)
    }

    @Test func isDirty_KindToggledAndToggledBack_IsFalse() {
        let model = RecipeFormViewModel()
        model.captureSnapshot()

        model.isNonSoapProduct = true
        model.isNonSoapProduct = false

        #expect(model.isDirty == false)
    }
}

@Suite("Recipe kind – calculated amounts", .serialized)
@MainActor
struct RecipeKindCalculationTests: RecipeFormTestHelpers {

    /// 1000 g of one oil (SAP 0.2, 0% superfat, 100% purity, 1.5:1 water) —
    /// 200 g lye and 300 g water as a soap recipe, none of it as a general one.
    private func makeGeneralModel() -> RecipeFormViewModel {
        let model = makeModelWithOils()
        model.isNonSoapProduct = true
        return model
    }

    @Test func calculatedLyeAmount_GeneralRecipe_IsNil() {
        #expect(makeGeneralModel().calculatedLyeAmount == nil)
    }

    @Test func calculatedWaterAmount_GeneralRecipe_IsNil() {
        #expect(makeGeneralModel().calculatedWaterAmount == nil)
    }

    @Test func calculatedNaOHAndKOHAmounts_GeneralRecipe_AreNil() {
        let model = makeGeneralModel()

        #expect(model.calculatedNaOHLyeAmount == nil)
        #expect(model.calculatedKOHLyeAmount == nil)
    }

    @Test func oilAmountCalculations_GeneralRecipe_StillResolveWeights() throws {
        let model = makeGeneralModel()

        let calculations = try #require(model.oilAmountCalculations)

        #expect(calculations.count == 1)
        #expect(calculations[0].weight == 1000)
        #expect(calculations[0].lye == 0)
    }

    @Test func oilAmountCalculations_GeneralRecipeWithInvalidLyePurity_StillResolve() throws {
        let model = makeGeneralModel()
        // Would abort the calculation for a soap recipe; a general one has no
        // lye configuration to be invalid.
        model.lyePurity = 0

        let calculations = try #require(model.oilAmountCalculations)

        #expect(calculations[0].weight == 1000)
    }

    @Test func calculatedAmountRows_GeneralRecipe_HaveNoLyeOrWaterRows() throws {
        let model = makeGeneralModel()

        let rows = try #require(model.calculatedAmountRows)
        let labels = rows.map(\.label)

        #expect(labels.contains("Coconut Oil"))
        #expect(labels.contains("Batch total"))
        #expect(labels.allSatisfy { !$0.contains("Water") })
        #expect(labels.allSatisfy { !$0.contains("NaOH") && !$0.contains("KOH") })
        #expect(rows.count == 2)
    }

    @Test func calculatedAmountRows_GeneralRecipe_BatchTotalIsTheBaseWeight() throws {
        let model = makeGeneralModel()

        let rows = try #require(model.calculatedAmountRows)
        let total = try #require(rows.last)

        #expect(total.label == "Batch total")
        #expect(total.weight == 1000)
        #expect(total.isSummary)
    }

    @Test func calculatedAmountRows_SoapRecipe_StillCarryLyeAndWater() throws {
        let model = makeModelWithOils()

        let rows = try #require(model.calculatedAmountRows)
        let labels = rows.map(\.label)

        #expect(labels.contains { $0.contains("NaOH") })
        #expect(labels.contains { $0.contains("Water") })
        #expect(model.calculatedLyeAmount == 200)
        #expect(model.calculatedWaterAmount == 300)
    }

    @Test func batchTotalWeight_GeneralRecipe_IsBaseWeightPlusAdditives() {
        let model = makeGeneralModel()
        let additive = Ingredient(name: "Shea Butter", unit: "g")
        model.addAdditive(additive)
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 50, unit: "g")

        #expect(model.batchTotalWeight == 1050)
    }

    @Test func batchTotalWeight_SoapRecipe_StillIncludesLyeAndWater() {
        let model = makeModelWithOils()

        #expect(model.batchTotalWeight == 1500)
    }

    @Test func wholeBatchBreakdown_GeneralRecipe_HasNoLyeRows() {
        let model = makeGeneralModel()
        model.lyeIngredient = Ingredient(name: "Sodium Hydroxide", unit: "g")

        #expect(model.wholeBatchBreakdown.lye.isEmpty)
    }

    @Test func extraIngredientData_GeneralRecipe_IsNil() {
        #expect(makeGeneralModel().extraIngredientData == nil)
    }

    @Test func creamSoapAdditions_GeneralRecipeWithStoredFlag_IsNil() {
        let model = makeGeneralModel()
        // Kept from before the switch, so the kind has to veto it.
        model.isCreamSoap = true

        #expect(model.creamSoapAdditions == nil)
    }

    @Test func creamSoapAdditions_SoapRecipe_StillBuilt() {
        let model = makeModelWithOils()
        model.isCreamSoap = true

        #expect(model.creamSoapAdditions != nil)
    }
}

@Suite("Recipe kind – merged ingredients section", .serialized)
@MainActor
struct RecipeKindIngredientRoutingTests: RecipeFormTestHelpers {

    private func makeIngredient(_ ctx: ModelContext, name: String, category: String?) -> Ingredient {
        let ingredient = Ingredient(name: name, unit: "g")
        if let category {
            let category = IngredientCategory(name: category)
            ctx.insert(category)
            ingredient.category = category
        }
        ctx.insert(ingredient)
        return ingredient
    }

    @Test func addIngredient_OilCategory_LandsInOilDrafts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()

        model.addIngredient(makeIngredient(ctx, name: "Soy Wax", category: IngredientCategory.Name.waxes))

        #expect(model.oilDrafts.count == 1)
        #expect(model.additiveDrafts.isEmpty)
        #expect(model.fragranceDrafts.isEmpty)
    }

    @Test func addIngredient_AdditiveCategory_LandsInAdditiveDrafts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()

        model.addIngredient(makeIngredient(ctx, name: "Mica", category: IngredientCategory.Name.additives))

        #expect(model.additiveDrafts.count == 1)
        #expect(model.oilDrafts.isEmpty)
    }

    @Test func addIngredient_FragranceCategory_LandsInFragranceDrafts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()

        model.addIngredient(makeIngredient(ctx, name: "Lavender EO", category: IngredientCategory.Name.fragrances))

        #expect(model.fragranceDrafts.count == 1)
        #expect(model.oilDrafts.isEmpty)
        #expect(model.additiveDrafts.isEmpty)
    }

    @Test func addIngredient_NoCategory_FallsBackToAdditive() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()

        model.addIngredient(makeIngredient(ctx, name: "Mystery", category: nil))

        #expect(model.additiveDrafts.count == 1)
    }

    /// The merged section is presentation only: an ingredient added through it
    /// keeps the role its category implies, which is what survives a switch back
    /// to soap and keeps the two sections correct again.
    @Test func addIngredient_MixedPicks_KeepTheirRolesThroughSaveAndLoad() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()
        model.name = "Lip Balm"
        model.isNonSoapProduct = true
        model.addIngredient(makeIngredient(ctx, name: "Beeswax", category: IngredientCategory.Name.waxes))
        model.addIngredient(makeIngredient(ctx, name: "Vitamin E", category: IngredientCategory.Name.additives))

        let saved = model.save(context: ctx)
        let reloaded = RecipeFormViewModel()
        reloaded.load(from: saved)

        #expect(reloaded.oilDrafts.map(\.ingredient.name) == ["Beeswax"])
        #expect(reloaded.additiveDrafts.map(\.ingredient.name) == ["Vitamin E"])
    }

    @Test func addIngredient_SameIngredientTwice_IsNotDuplicated() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()
        let wax = makeIngredient(ctx, name: "Soy Wax", category: IngredientCategory.Name.waxes)

        model.addIngredient(wax)
        model.addIngredient(wax)

        #expect(model.oilDrafts.count == 1)
    }
}

@Suite("Recipe kind – list row", .serialized)
@MainActor
struct RecipeKindRowSummaryTests: RecipeRowSummaryTestHelpers {

    @Test func soapType_GeneralRecipe_IsNil() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.recipeKind = RecipeKind.general.rawValue

        #expect(RecipeRowSummary(recipe: recipe).soapType == nil)
    }

    @Test func kindLabel_GeneralRecipe_IsNeutral() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.recipeKind = RecipeKind.general.rawValue

        #expect(RecipeRowSummary(recipe: recipe).kindLabel == "Non-soap product")
    }

    @Test func subtitle_GeneralRecipe_NamesNoSoapType() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.recipeKind = RecipeKind.general.rawValue
        recipe.totalOilWeight = 500

        let subtitle = RecipeRowSummary(recipe: recipe).subtitle

        #expect(subtitle.hasPrefix("Non-soap product · "))
        for soapType in [SoapType.solid, .cream, .liquid] {
            #expect(!subtitle.contains(soapType.label))
        }
    }

    @Test func subtitle_SoapRecipe_StillNamesTheSoapType() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = Recipe.mock(in: ctx)
        recipe.totalOilWeight = 500

        #expect(RecipeRowSummary(recipe: recipe).subtitle.hasPrefix("Solid bar soap · "))
    }
}
