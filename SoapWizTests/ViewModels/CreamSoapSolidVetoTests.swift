import Testing
import Foundation
@testable import SoapWiz

@Suite("Cream soap solid veto", .serialized)
@MainActor
struct CreamSoapSolidVetoTests {

    private func makeModel(lyeType: String = "NaOH") -> RecipeFormViewModel {
        let oil = Ingredient(name: "Test Oil", unit: "g")
        oil.sapValue = 0.134
        oil.kohSapValue = 0.188
        let model = RecipeFormViewModel()
        model.weightUnit = "g"
        model.lyeType = lyeType
        model.lyePurity = 100
        model.superFat = 5
        model.addOil(oil)
        model.oilDrafts[0].amount = 1000
        model.isCreamSoap = true
        return model
    }

    private func makeDualLyeModel(naohPercentage: Double) -> RecipeFormViewModel {
        let model = makeModel()
        model.useHybrid = true
        model.kohPercentage = 100 - naohPercentage
        model.naohPercentage = naohPercentage
        model.kohPurity = 100
        model.naohPurity = 100
        return model
    }

    private func hasWaterRow(_ model: RecipeFormViewModel) -> Bool {
        model.calculatedAmountRows?.contains { $0.label.contains("Additional Water for Cream Soap") } ?? false
    }

    private func hasGlycerineRow(_ model: RecipeFormViewModel) -> Bool {
        model.extraIngredientData?.sectionB.contains { $0.label == LyeCalculator.creamSoapGlycerineLabel } ?? false
    }

    @Test func solidNaOH_CreamFlagOn_ProducesNoCreamRows() {
        let model = makeModel()

        #expect(model.soapType == .solid)
        #expect(model.isCreamSoap)
        #expect(!model.creamSoapActive)
        #expect(!model.lyeCalculator.isCreamSoap)
        #expect(!hasWaterRow(model))
        #expect(!hasGlycerineRow(model))
    }

    @Test func singleKOH_CreamFlagOn_ProducesBothRows() {
        let model = makeModel(lyeType: "KOH")

        #expect(model.creamSoapActive)
        #expect(hasWaterRow(model))
        #expect(hasGlycerineRow(model))
    }

    @Test func dualLye_CreamType_CreamFlagOn_ProducesBothRows() {
        let model = makeDualLyeModel(naohPercentage: 30)

        #expect(model.soapType == .cream)
        #expect(model.creamSoapActive)
        #expect(hasWaterRow(model))
        #expect(hasGlycerineRow(model))
    }

    @Test func dualLye_LiquidType_CreamFlagOn_ProducesBothRows() {
        let model = makeDualLyeModel(naohPercentage: 5)

        #expect(model.soapType == .liquid)
        #expect(hasWaterRow(model))
        #expect(hasGlycerineRow(model))
    }

    @Test func switchingKOHToNaOHAndBack_KeepsFlagAndRestoresRows() {
        let model = makeModel(lyeType: "KOH")
        #expect(hasWaterRow(model))

        model.lyeType = "NaOH"
        #expect(model.isCreamSoap)
        #expect(!hasWaterRow(model))
        #expect(!hasGlycerineRow(model))

        model.lyeType = "KOH"
        #expect(hasWaterRow(model))
        #expect(hasGlycerineRow(model))
    }

    @Test func reconcile_SolidRecipeWithCreamOn_DoesNotAddGlycerine() {
        let model = makeModel()
        let glycerine = Ingredient(name: "Glycerin", unit: "g")
        model.creamSoapGlycerinePending = true

        model.reconcileCreamSoapGlycerine(from: [glycerine])

        #expect(model.additiveDrafts.isEmpty)
        #expect(model.creamSoapGlycerinePending)
    }

    @Test func reconcile_KOHRecipeWithCreamOn_AddsGlycerine() {
        let model = makeModel(lyeType: "KOH")
        let glycerine = Ingredient(name: "Glycerin", unit: "g")
        model.creamSoapGlycerinePending = true

        model.reconcileCreamSoapGlycerine(from: [glycerine])

        #expect(model.additiveDrafts.count == 1)
        #expect(!model.creamSoapGlycerinePending)
    }
}
