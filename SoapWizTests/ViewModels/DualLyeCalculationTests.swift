import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Dual lye calculation", .serialized)
@MainActor
struct DualLyeCalculationTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([Recipe.self, RecipeIngredient.self, RecipeProduct.self, Ingredient.self, IngredientPurchase.self, IngredientCategory.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return (container, container.mainContext)
    }

    /// Direct-weight recipe with a single oil of the given weight and sap values.
    private func makeModel(weight: Double, naohSap: Double, kohSap: Double) -> RecipeFormViewModel {
        let oil = Ingredient(name: "Test Oil", unit: "g")
        oil.sapValue = naohSap
        oil.kohSapValue = kohSap
        let model = RecipeFormViewModel()
        model.weightUnit = "g"
        model.superFat = 0
        model.addOil(oil)
        model.oilDrafts[0].amount = weight
        return model
    }

    private func isClose(_ actual: Double?, _ expected: Double, tol: Double = 1e-6) -> Bool {
        guard let actual else { return false }
        return abs(actual - expected) < tol
    }

    // MARK: - Single lye

    @Test func singleLye_FullPurity_NoSuperFat_IsWeightTimesSap() {
        let model = makeModel(weight: 1000, naohSap: 0.134, kohSap: 0.188)
        model.lyePurity = 100
        #expect(isClose(model.calculatedLyeAmount, 134))
        #expect(isClose(model.calculatedNaOHLyeAmount, 134))
        #expect(isClose(model.calculatedKOHLyeAmount, 0))
    }

    @Test func singleLye_AppliesPurity() {
        let model = makeModel(weight: 1000, naohSap: 0.134, kohSap: 0.188)
        model.lyePurity = 99
        #expect(isClose(model.calculatedLyeAmount, 134 / 0.99))
    }

    @Test func singleKOH_UsesKOHSapAndIsLiquid() {
        let model = makeModel(weight: 1000, naohSap: 0.134, kohSap: 0.188)
        model.lyeType = "KOH"
        model.lyePurity = 100
        #expect(isClose(model.calculatedKOHLyeAmount, 188))
        #expect(isClose(model.calculatedNaOHLyeAmount, 0))
        #expect(model.soapType == .liquid)
    }

    @Test func setLyeType_ToKOH_DefaultsPurityTo90() {
        let model = RecipeFormViewModel() // lyePurity 99
        model.setLyeType("KOH")
        #expect(model.lyeType == "KOH")
        #expect(model.lyePurity == 90)
    }

    @Test func setLyeType_BackToNaOH_RestoresPurity99() {
        let model = RecipeFormViewModel()
        model.setLyeType("KOH")
        model.setLyeType("NaOH")
        #expect(model.lyeType == "NaOH")
        #expect(model.lyePurity == 99)
    }

    @Test func setLyeType_KeepsCustomPurity() {
        let model = RecipeFormViewModel()
        model.lyePurity = 95
        model.setLyeType("KOH")
        #expect(model.lyePurity == 95) // not a standard default, so preserved
    }

    @Test func singleLye_AppliesSuperFat() {
        let model = makeModel(weight: 1000, naohSap: 0.134, kohSap: 0.188)
        model.lyePurity = 100
        model.superFat = 5
        #expect(isClose(model.calculatedLyeAmount, 134 * 0.95))
    }

    // MARK: - Dual lye

    @Test func dualLye_SplitsByShareAndSap() {
        let model = makeModel(weight: 1000, naohSap: 0.134, kohSap: 0.188)
        model.useHybrid = true
        model.kohPercentage = 90
        model.naohPercentage = 10
        model.kohPurity = 100
        model.naohPurity = 100

        #expect(isClose(model.calculatedNaOHLyeAmount, 0.10 * 1000 * 0.134))   // 13.4
        #expect(isClose(model.calculatedKOHLyeAmount, 0.90 * 1000 * 0.188))    // 169.2
        #expect(isClose(model.calculatedLyeAmount, 13.4 + 169.2))             // 182.6
    }

    @Test func dualLye_AppliesEachPurity() {
        let model = makeModel(weight: 1000, naohSap: 0.134, kohSap: 0.188)
        model.useHybrid = true
        model.kohPercentage = 90
        model.naohPercentage = 10
        model.kohPurity = 90
        model.naohPurity = 99

        #expect(isClose(model.calculatedNaOHLyeAmount, 0.10 * 1000 * 0.134 / 0.99))
        #expect(isClose(model.calculatedKOHLyeAmount, 0.90 * 1000 * 0.188 / 0.90))
    }

    @Test func dualLye_AppliesSuperFatToBothComponents() {
        let model = makeModel(weight: 1000, naohSap: 0.134, kohSap: 0.188)
        model.useHybrid = true
        model.kohPercentage = 90
        model.naohPercentage = 10
        model.kohPurity = 100
        model.naohPurity = 100
        model.superFat = 5

        #expect(isClose(model.calculatedNaOHLyeAmount, 13.4 * 0.95))
        #expect(isClose(model.calculatedKOHLyeAmount, 169.2 * 0.95))
    }

    @Test func dualLye_PureKOH_HasNoNaOH() {
        let model = makeModel(weight: 1000, naohSap: 0.134, kohSap: 0.188)
        model.useHybrid = true
        model.setKOHPercentage(100)
        model.kohPurity = 100
        model.naohPurity = 100

        #expect(isClose(model.calculatedNaOHLyeAmount, 0))
        #expect(isClose(model.calculatedKOHLyeAmount, 1000 * 0.188))
    }

    @Test func waterAmount_DualLye_IsTotalLyeTimesRatio() {
        let model = makeModel(weight: 1000, naohSap: 0.134, kohSap: 0.188)
        model.useHybrid = true
        model.kohPercentage = 90
        model.naohPercentage = 10
        model.kohPurity = 100
        model.naohPurity = 100
        model.waterParts = 1.5

        #expect(isClose(model.calculatedWaterAmount, 182.6 * 1.5))
    }

    // MARK: - Percentage helpers

    @Test func setKOHPercentage_ComplementsNaOH() {
        let model = RecipeFormViewModel()
        model.setKOHPercentage(70)
        #expect(model.kohPercentage == 70)
        #expect(model.naohPercentage == 30)
    }

    @Test func setNaOHPercentage_ComplementsKOH() {
        let model = RecipeFormViewModel()
        model.setNaOHPercentage(25)
        #expect(model.naohPercentage == 25)
        #expect(model.kohPercentage == 75)
    }

    @Test func setKOHPercentage_ClampsAbove100() {
        let model = RecipeFormViewModel()
        model.setKOHPercentage(140)
        #expect(model.kohPercentage == 100)
        #expect(model.naohPercentage == 0)
    }

    // MARK: - soapType classifier

    @Test func soapType_SingleNaOH_IsSolid() {
        #expect(SoapType.classify(useHybrid: false, naohPercentage: 0, lyeType: "NaOH") == .solid)
    }

    @Test func soapType_SingleKOH_IsLiquid() {
        #expect(SoapType.classify(useHybrid: false, naohPercentage: 0, lyeType: "KOH") == .liquid)
    }

    @Test func soapType_DualHighNaOH_IsCream() {
        #expect(SoapType.classify(useHybrid: true, naohPercentage: 20, lyeType: "NaOH") == .cream)
    }

    @Test func soapType_DualPureKOH_IsLiquid() {
        #expect(SoapType.classify(useHybrid: true, naohPercentage: 0, lyeType: "NaOH") == .liquid)
    }

    @Test func soapType_DualLowNaOH_IsLiquid() {
        #expect(SoapType.classify(useHybrid: true, naohPercentage: 10, lyeType: "NaOH") == .liquid)
    }

    @Test func soapType_ModelReflectsConfiguration() {
        let model = RecipeFormViewModel()
        #expect(model.soapType == .solid)
        model.useHybrid = true
        model.setKOHPercentage(90) // naoh 10 → liquid
        #expect(model.soapType == .liquid)
        model.setNaOHPercentage(20) // naoh 20 → cream
        #expect(model.soapType == .cream)
    }

    // MARK: - Cost split

    @Test func costBreakdown_DualLye_SplitsAcrossNaOHAndKOHIngredients() throws {
        let (container, ctx) = try makeContext()
        _ = container

        let naoh = Ingredient(name: "Sodium Hydroxide", unit: "g")
        let koh = Ingredient(name: "Potassium Hydroxide", unit: "g")
        ctx.insert(naoh)
        ctx.insert(koh)
        naoh.purchases.append(purchase(quantity: 1000, price: 10))  // 0.01 / g
        koh.purchases.append(purchase(quantity: 1000, price: 20))   // 0.02 / g

        let model = makeModel(weight: 1000, naohSap: 0.134, kohSap: 0.188)
        model.useHybrid = true
        model.kohPercentage = 90
        model.naohPercentage = 10
        model.kohPurity = 100
        model.naohPurity = 100
        model.lyeIngredient = naoh
        model.kohLyeIngredient = koh

        let lyeRows = model.wholeBatchBreakdown.lye
        #expect(lyeRows.count == 2)

        let naohRow = try #require(lyeRows.first { $0.ingredient.name == "Sodium Hydroxide" })
        let kohRow = try #require(lyeRows.first { $0.ingredient.name == "Potassium Hydroxide" })
        #expect(isClose(naohRow.ingredientAmount, 13.4))
        #expect(isClose(kohRow.ingredientAmount, 169.2))
        #expect(isClose(naohRow.cost, 13.4 * 0.01))
        #expect(isClose(kohRow.cost, 169.2 * 0.02))
    }

    @Test func costBreakdown_SingleLye_HasOneLyeRow() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let naoh = Ingredient(name: "Sodium Hydroxide", unit: "g")
        ctx.insert(naoh)
        naoh.purchases.append(purchase(quantity: 1000, price: 10))

        let model = makeModel(weight: 1000, naohSap: 0.134, kohSap: 0.188)
        model.lyePurity = 100
        model.lyeIngredient = naoh

        #expect(model.wholeBatchBreakdown.lye.count == 1)
    }

    // MARK: - Acid neutralization split

    @Test func acidNeutralization_SingleLye_AddsNaOHOnly() {
        let model = makeModel(weight: 1000, naohSap: 0.134, kohSap: 0.188)
        model.lyePurity = 100
        let citric = Ingredient(name: "Citric Acid", unit: "g")
        model.addAdditive(citric)
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 10)

        // 1000 * 0.134 oil lye + 10 g citric * 0.625 acid lye, all NaOH.
        #expect(isClose(model.calculatedNaOHLyeAmount, 134 + 10 * 0.625))
        #expect(isClose(model.calculatedKOHLyeAmount, 0))
    }

    @Test func acidNeutralization_DualLye_SplitsBetweenNaOHAndKOH() {
        let model = makeModel(weight: 1000, naohSap: 0.134, kohSap: 0.188)
        model.useHybrid = true
        model.kohPercentage = 90
        model.naohPercentage = 10
        model.kohPurity = 100
        model.naohPurity = 100
        let citric = Ingredient(name: "Citric Acid", unit: "g")
        model.addAdditive(citric)
        model.updateAdditive(id: model.additiveDrafts[0].id, amount: 10)

        let oilNaOH = 0.10 * 1000 * 0.134
        let oilKOH = 0.90 * 1000 * 0.188
        let acidNaOH = 10 * 0.625 * 0.10
        let acidKOH = 10 * 0.625 * RecipeFormViewModel.kohPerNaOHMass * 0.90
        #expect(isClose(model.calculatedNaOHLyeAmount, oilNaOH + acidNaOH))
        #expect(isClose(model.calculatedKOHLyeAmount, oilKOH + acidKOH))
    }

    @Test func extras_DualLye_CitricHasBothLyeAmounts() throws {
        let model = makeModel(weight: 1000, naohSap: 0.134, kohSap: 0.188)
        model.useHybrid = true
        model.kohPercentage = 90
        model.naohPercentage = 10

        let data = try #require(model.extraIngredientData)
        let citric = try #require(data.sectionA.first { $0.label == "Citric Acid Powder" })
        #expect(citric.naohLye != nil)
        #expect(citric.kohLye != nil)
        let lactic = try #require(data.sectionB.first { $0.label == "Lactic Acid" })
        #expect(lactic.naohLye != nil)
        #expect(lactic.kohLye != nil)
    }

    @Test func extras_SingleLye_CitricHasNoKOHSolution() throws {
        let model = makeModel(weight: 1000, naohSap: 0.134, kohSap: 0.188)
        let data = try #require(model.extraIngredientData)
        let citric = try #require(data.sectionA.first { $0.label == "Citric Acid Powder" })
        #expect(citric.naohLye != nil)
        #expect(citric.kohLye == nil)
    }

    @Test func extras_DualLye_MatchesLyeCalcFigures() throws {
        // LyeCalc reference: oils 1000, KOH 90% @90% purity, NaOH 10% @99% purity.
        // Citric 1% (10 g) → NaOH 0.63 g, KOH 8.76 g.
        let model = makeModel(weight: 1000, naohSap: 0.134, kohSap: 0.188)
        model.weightUnit = "%"
        model.totalOilWeight = 1000
        model.oilDrafts[0].amount = 100
        model.useHybrid = true
        model.kohPercentage = 90
        model.naohPercentage = 10
        model.kohPurity = 90
        model.naohPurity = 99

        let data = try #require(model.extraIngredientData)
        let citric = try #require(data.sectionA.first { $0.label == "Citric Acid Powder" })
        let naoh = try #require(citric.naohLye)
        let koh = try #require(citric.kohLye)
        #expect(abs(naoh.v1 - 0.63) < 0.01)
        #expect(abs(koh.v1 - 8.76) < 0.01)
    }

    @Test func extras_DualPureKOH_CitricHasNoNaOHSolution() throws {
        let model = makeModel(weight: 1000, naohSap: 0.134, kohSap: 0.188)
        model.useHybrid = true
        model.setKOHPercentage(100)

        let data = try #require(model.extraIngredientData)
        let citric = try #require(data.sectionA.first { $0.label == "Citric Acid Powder" })
        #expect(citric.naohLye == nil)
        #expect(citric.kohLye != nil)
    }

    private func purchase(quantity: Double, price: Double) -> IngredientPurchase {
        IngredientPurchase(
            dateOfPurchase: .now, quantity: quantity, totalPrice: price,
            badge: "", journalCode: "", expiryDate: nil, openingDate: nil
        )
    }
}
