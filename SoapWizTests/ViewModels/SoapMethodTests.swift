import Testing
import Foundation
@testable import SoapWiz

/// Cream Soap & Catherine Failor method (SW-86). Reference figures verified
/// against LightCalc: avocado oil 1000 g, dual lye 90% KOH / 10% NaOH at 100%
/// purity, 5% super fat, 2:1 water — sap NaOH 0.132, KOH 0.186.
@Suite("Soap methods", .serialized)
@MainActor
struct SoapMethodTests {

    /// Dual-lye liquid-soap model (90% KOH / 10% NaOH, 100% purity) measured in
    /// direct grams, so `cfmActive` is true once `useCFM` is set.
    private func makeLiquidModel(weight: Double = 1000, superFat: Double = 5, waterParts: Double = 2) -> RecipeFormViewModel {
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
        model.superFat = superFat
        model.waterParts = waterParts
        model.addOil(oil)
        model.oilDrafts[0].amount = weight
        return model
    }

    /// Single-NaOH solid bar (sap NaOH 0.134 / KOH 0.188, 1000 g, 5% SF) with
    /// CFM requested — inert, because the soap is solid.
    private func makeSolidModel() -> RecipeFormViewModel {
        let oil = Ingredient(name: "Test Oil", unit: "g")
        oil.sapValue = 0.134
        oil.kohSapValue = 0.188
        let model = RecipeFormViewModel()
        model.weightUnit = "g"
        model.lyePurity = 100
        model.superFat = 5
        model.addOil(oil)
        model.oilDrafts[0].amount = 1000
        model.useCFM = true
        return model
    }

    private func isClose(_ actual: Double?, _ expected: Double, tol: Double = 0.01) -> Bool {
        guard let actual else { return false }
        return abs(actual - expected) < tol
    }

    /// Weight of the first calculated-amounts row whose label contains `fragment`.
    private func rowWeight(_ model: RecipeFormViewModel, containing fragment: String) -> Double? {
        model.calculatedAmountRows?.first { $0.label.contains(fragment) }?.weight
    }

    // MARK: - CFM lye (0% super fat + 10% excess)

    @Test func cfm_NonSolid_AppliesTenPercentExcessAtZeroSuperFat() {
        let model = makeLiquidModel()
        model.useCFM = true
        #expect(model.cfmNeutralizer == .boricAcid) // default
        // 0% super fat + 10% excess → base sap lye × 1.10.
        #expect(isClose(model.calculatedNaOHLyeAmount, 0.10 * 1000 * 0.132 * 1.10)) // 14.52
        #expect(isClose(model.calculatedKOHLyeAmount, 0.90 * 1000 * 0.186 * 1.10))  // 184.14
    }

    @Test func cfm_Off_RespectsSuperFat() {
        let model = makeLiquidModel(superFat: 5)
        // Without CFM the lye follows the 5% super-fat discount.
        #expect(isClose(model.calculatedNaOHLyeAmount, 0.10 * 1000 * 0.132 * 0.95))
        #expect(isClose(model.calculatedKOHLyeAmount, 0.90 * 1000 * 0.186 * 0.95))
    }

    @Test func cfm_SolidSoap_HasNoEffect() {
        let model = makeSolidModel()

        #expect(model.soapType == .solid)
        #expect(isClose(model.calculatedLyeAmount, 1000 * 0.134 * 0.95)) // super fat, no excess
        #expect(rowWeight(model, containing: "Excess Lye") == nil)
        #expect(rowWeight(model, containing: "Boric Acid") == nil)
    }

    // MARK: - CFM water (uses normal super fat, not the excess lye)

    @Test func cfm_Water_UsesNormalSuperFatLye_NotExcess() {
        let model = makeLiquidModel(superFat: 5, waterParts: 2)
        model.useCFM = true
        // Water = ratio × base lye at the recipe's 5% super fat (180.6 × 0.95 × 2).
        #expect(isClose(model.calculatedWaterAmount, 180.6 * 0.95 * 2)) // 343.14
    }

    @Test func cfm_LyeRows_CarryExcessLabel() {
        let model = makeLiquidModel()
        model.useCFM = true
        #expect(isClose(rowWeight(model, containing: "KOH (0% Superfat + 10% Excess Lye)"), 184.14))
        #expect(isClose(rowWeight(model, containing: "NaOH (0% Superfat + 10% Excess Lye)"), 14.52))
    }

    // MARK: - Neutraliser solution (¾ oz per lb of soap weight)

    @Test func cfm_BoricAcid_SplitsTwentyEighty() {
        let model = makeLiquidModel()
        model.useCFM = true
        model.cfmNeutralizer = .boricAcid
        // Soap weight 1523.74 × 0.046875 = 71.43 solution; 20% acid / 80% water.
        #expect(isClose(rowWeight(model, containing: "Boric Acid (20% of Solution)"), 14.29))
        #expect(isClose(rowWeight(model, containing: "Water for Boric Acid Solution (80% of Solution)"), 57.14))
    }

    @Test func cfm_Borax_SplitsThirtyThreeSixtySeven() {
        let model = makeLiquidModel()
        model.useCFM = true
        model.cfmNeutralizer = .borax
        #expect(isClose(rowWeight(model, containing: "Borax (33% of Solution)"), 23.57))
        #expect(isClose(rowWeight(model, containing: "Water for Borax Solution (67% of Solution)"), 47.85))
    }

    @Test func cfm_Off_HasNoNeutraliserRows() {
        let model = makeLiquidModel()
        #expect(rowWeight(model, containing: "Boric Acid") == nil)
        #expect(rowWeight(model, containing: "Borax") == nil)
    }

    // MARK: - Neutraliser dose as a consumable weight (SW-161)

    @Test func cfm_NeutralizerWeights_BoricAcid_MatchRows() {
        let model = makeLiquidModel()
        model.useCFM = true
        model.cfmNeutralizer = .boricAcid
        // Same split as the amounts-table rows, now exposed as consumable weights.
        #expect(isClose(model.lyeCalculator.cfmNeutralizerSolidWeight, 14.29))
        #expect(isClose(model.lyeCalculator.cfmNeutralizerWaterWeight, 57.14))
    }

    @Test func cfm_NeutralizerWeights_Borax_MatchRows() {
        let model = makeLiquidModel()
        model.useCFM = true
        model.cfmNeutralizer = .borax
        #expect(isClose(model.lyeCalculator.cfmNeutralizerSolidWeight, 23.57))
        #expect(isClose(model.lyeCalculator.cfmNeutralizerWaterWeight, 47.85))
    }

    @Test func cfm_Off_NeutralizerWeightsAreNil() {
        let model = makeLiquidModel()
        #expect(model.lyeCalculator.cfmNeutralizerSolidWeight == nil)
        #expect(model.lyeCalculator.cfmNeutralizerWaterWeight == nil)
    }

    @Test func cfm_SolidSoap_NeutralizerWeightsAreNil() {
        let model = makeSolidModel()

        #expect(model.lyeCalculator.cfmNeutralizerSolidWeight == nil)
        #expect(model.lyeCalculator.cfmNeutralizerWaterWeight == nil)
    }

    // MARK: - Cream soap additions

    /// The suggested glycerine amount, or nil when it isn't offered.
    private func glycerineSuggestion(_ model: RecipeFormViewModel) -> Double? {
        model.extraIngredientData?.sectionB
            .first { $0.label.contains("Glycerine") }?.minValue
    }

    @Test func creamSoap_AddsAdvisoryWaterToCalculatedAmounts() throws {
        let model = makeLiquidModel()
        model.isCreamSoap = true
        let rows = try #require(model.calculatedAmountRows)
        let water = try #require(rows.first { $0.label.contains("Additional Water for Cream Soap") })
        #expect(isClose(water.weight, 1000 * 0.792)) // 792
        // The timing warning rides along as the row's caption.
        #expect(water.note?.isEmpty == false)
    }

    /// Dilution water is advisory: shown, but never folded into the batch total.
    @Test func creamSoap_AdvisoryWater_DoesNotChangeBatchTotal() throws {
        let offModel = makeLiquidModel()
        let onModel = makeLiquidModel()
        onModel.isCreamSoap = true
        let offTotal = try #require(rowWeight(offModel, containing: "Batch total"))
        let onTotal = try #require(rowWeight(onModel, containing: "Batch total"))
        #expect(isClose(onTotal, offTotal))
    }

    /// The advisory water sits *below* the batch total and shows no percentage,
    /// so the rows above still visibly sum to the total.
    @Test func creamSoap_AdvisoryWater_SitsBelowBatchTotalWithNoPct() throws {
        let model = makeLiquidModel()
        model.isCreamSoap = true
        let rows = try #require(model.calculatedAmountRows)
        let totalIdx = try #require(rows.firstIndex { $0.label.contains("Batch total") })
        let waterIdx = try #require(rows.firstIndex { $0.label.contains("Additional Water for Cream Soap") })
        #expect(waterIdx > totalIdx)
        #expect(rows[waterIdx].pct == nil)
    }

    @Test func creamSoap_OffersGlycerineAsCostableExtra() throws {
        let model = makeLiquidModel()
        model.isCreamSoap = true
        let glycerine = try #require(glycerineSuggestion(model))
        #expect(isClose(glycerine, 1000 * 0.0625)) // 62.50
    }

    @Test func creamSoap_Off_HasNoAdditions() {
        let model = makeLiquidModel()
        #expect(rowWeight(model, containing: "Additional Water for Cream Soap") == nil)
        #expect(glycerineSuggestion(model) == nil)
    }

    @Test func creamSoap_NoOils_HasNoAdditions() {
        let model = RecipeFormViewModel()
        model.weightUnit = "g"
        model.isCreamSoap = true
        #expect(rowWeight(model, containing: "Additional Water for Cream Soap") == nil)
        #expect(glycerineSuggestion(model) == nil)
    }

    @Test func creamSoap_IndependentOfCFM_BothStack() throws {
        let model = makeLiquidModel()
        model.isCreamSoap = true
        model.useCFM = true
        // Both additions present *and* CFM excess lye applied.
        #expect(rowWeight(model, containing: "Additional Water for Cream Soap") != nil)
        #expect(glycerineSuggestion(model) != nil)
        #expect(isClose(model.calculatedKOHLyeAmount, 184.14))
    }

    // MARK: - Cream soap method toggle (auto-adding glycerine)

    private func glycerineDraft(_ model: RecipeFormViewModel) -> IngredientAmountDraft? {
        model.additiveDrafts.first { $0.ingredient.name.localizedCaseInsensitiveContains("glycerin") }
    }

    @Test func setCreamSoap_On_WithGlycerineInInventory_AddsCostedDraft() throws {
        let model = makeLiquidModel()
        let glycerine = Ingredient(name: "Glycerin", unit: "g")

        model.setCreamSoap(true, from: [glycerine])

        let draft = try #require(glycerineDraft(model))
        #expect(isClose(draft.amount, 1000 * 0.0625)) // 62.50
    }

    @Test func setCreamSoap_On_WithNoGlycerineInInventory_AddsNothing() {
        let model = makeLiquidModel()

        model.setCreamSoap(true, from: [])

        #expect(model.isCreamSoap)               // flag still flips
        #expect(glycerineDraft(model) == nil)    // but nothing to cost against
    }

    @Test func setCreamSoap_Off_RemovesUneditedGlycerine() throws {
        let model = makeLiquidModel()
        let glycerine = Ingredient(name: "Glycerin", unit: "g")
        model.setCreamSoap(true, from: [glycerine])
        try #require(glycerineDraft(model))

        model.setCreamSoap(false, from: [glycerine])

        #expect(glycerineDraft(model) == nil)
    }

    @Test func setCreamSoap_Off_KeepsEditedGlycerine() throws {
        let model = makeLiquidModel()
        let glycerine = Ingredient(name: "Glycerin", unit: "g")
        model.setCreamSoap(true, from: [glycerine])
        let idx = try #require(model.additiveDrafts.firstIndex { $0.ingredient === glycerine })
        model.additiveDrafts[idx].amount = 90 // user changes it — now theirs

        model.setCreamSoap(false, from: [glycerine])

        #expect(glycerineDraft(model) != nil)
    }

    @Test func setCreamSoap_On_BeforeOils_DefersUntilOilsAdded() throws {
        // Toggle the method on an empty recipe: nothing to size the dose yet.
        let model = RecipeFormViewModel()
        model.weightUnit = "g"
        let glycerine = Ingredient(name: "Glycerin", unit: "g")
        model.setCreamSoap(true, from: [glycerine])
        #expect(glycerineDraft(model) == nil)
        #expect(model.creamSoapGlycerinePending)

        // Oils arrive; the ingredients tab reconciles and the add lands.
        let oil = Ingredient(name: "Olive Oil", unit: "g")
        oil.sapValue = 0.134
        oil.kohSapValue = 0.19
        model.addOil(oil)
        model.oilDrafts[0].amount = 1000
        model.reconcileCreamSoapGlycerine(from: [glycerine])

        let draft = try #require(glycerineDraft(model))
        #expect(isClose(draft.amount, 1000 * 0.0625))
        #expect(!model.creamSoapGlycerinePending)
    }

    @Test func reconcile_AfterUserRemovesGlycerine_DoesNotReAdd() throws {
        let model = makeLiquidModel()
        let glycerine = Ingredient(name: "Glycerin", unit: "g")
        model.setCreamSoap(true, from: [glycerine])            // added
        let idx = try #require(model.additiveDrafts.firstIndex { $0.ingredient === glycerine })
        model.additiveDrafts.remove(at: idx)                   // user unchecks it

        model.reconcileCreamSoapGlycerine(from: [glycerine])   // oils change later

        #expect(glycerineDraft(model) == nil)                  // stays gone
    }

    @Test func setCreamSoap_Off_KeepsManuallyReAddedGlycerine() throws {
        let model = makeLiquidModel()
        let glycerine = Ingredient(name: "Glycerin", unit: "g")
        model.setCreamSoap(true, from: [glycerine])       // auto-added at the suggested amount
        let amount = try #require(glycerineDraft(model)).amount
        model.toggleExtra(glycerine, amount: amount)      // user removes it via the extras row
        model.toggleExtra(glycerine, amount: amount)      // then re-adds it, same amount

        model.setCreamSoap(false, from: [glycerine])      // turning the method off

        // It's the user's now, not our auto-add, so it must survive.
        #expect(glycerineDraft(model) != nil)
    }

    @Test func setCreamSoap_On_DoesNotDuplicateUserGlycerine() {
        let model = makeLiquidModel()
        let glycerine = Ingredient(name: "Glycerin", unit: "g")
        model.additiveDrafts.append(IngredientAmountDraft(ingredient: glycerine, amount: 10, unit: "g"))

        model.setCreamSoap(true, from: [glycerine])

        #expect(model.additiveDrafts.filter { $0.ingredient === glycerine }.count == 1)
    }
}
