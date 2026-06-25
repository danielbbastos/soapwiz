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
        let oil = Ingredient(name: "Test Oil", unit: "g")
        oil.sapValue = 0.134
        oil.kohSapValue = 0.188
        let model = RecipeFormViewModel()
        model.weightUnit = "g"
        model.lyePurity = 100
        model.superFat = 5
        model.addOil(oil)
        model.oilDrafts[0].amount = 1000
        model.useCFM = true // single NaOH → solid → CFM inert

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

    // MARK: - Cream soap additions

    @Test func creamSoap_AddsWaterAndGlycerineScaledToOils() throws {
        let model = makeLiquidModel()
        model.isCreamSoap = true
        let rows = try #require(model.creamSoapAdditions)
        let water = try #require(rows.first { $0.label.contains("Additional Water") })
        let glycerine = try #require(rows.first { $0.label.contains("Glycerine") })
        #expect(isClose(water.minValue, 1000 * 0.792))      // 792
        #expect(isClose(glycerine.minValue, 1000 * 0.0625)) // 62.50
    }

    @Test func creamSoap_Off_HasNoAdditions() {
        let model = makeLiquidModel()
        #expect(model.creamSoapAdditions == nil)
    }

    @Test func creamSoap_NoOils_HasNoAdditions() {
        let model = RecipeFormViewModel()
        model.weightUnit = "g"
        model.isCreamSoap = true
        #expect(model.creamSoapAdditions == nil)
    }

    @Test func creamSoap_IndependentOfCFM_BothStack() throws {
        let model = makeLiquidModel()
        model.isCreamSoap = true
        model.useCFM = true
        // Cream additions present *and* CFM excess lye applied.
        #expect(model.creamSoapAdditions?.count == 2)
        #expect(isClose(model.calculatedKOHLyeAmount, 184.14))
    }
}
