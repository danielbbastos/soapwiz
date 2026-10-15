import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Liquid soap dilution note", .serialized)
@MainActor
struct LiquidSoapDilutionNoteTests {

    private func makeModel() -> RecipeFormViewModel {
        let oil = Ingredient(name: "Test Oil", unit: "g")
        oil.sapValue = 0.134
        oil.kohSapValue = 0.188
        let model = RecipeFormViewModel()
        model.weightUnit = "g"
        model.superFat = 0
        model.addOil(oil)
        model.oilDrafts[0].amount = 1000
        return model
    }

    private func makeHybridModel(naohPercentage: Double) -> RecipeFormViewModel {
        let model = makeModel()
        model.useHybrid = true
        model.naohPercentage = naohPercentage
        model.kohPercentage = 100 - naohPercentage
        return model
    }

    private func noteRows(_ model: RecipeFormViewModel) throws -> [CalculatedAmountRow] {
        let rows = try #require(model.calculatedAmountRows)
        return rows.filter { $0.note == LyeCalculator.liquidSoapDilutionNote }
    }

    @Test func singleKOH_BatchTotalCarriesNote() throws {
        let model = makeModel()
        model.lyeType = "KOH"

        let rows = try #require(model.calculatedAmountRows)
        let batchTotal = try #require(rows.first { $0.label == "Batch total" })

        #expect(batchTotal.note == LyeCalculator.liquidSoapDilutionNote)
    }

    @Test func singleKOH_NoteAppearsOnlyOnBatchTotalRow() throws {
        let model = makeModel()
        model.lyeType = "KOH"

        let withNote = try noteRows(model)

        #expect(withNote.count == 1)
        #expect(withNote.first?.isSummary == true)
        #expect(withNote.first?.label == "Batch total")
    }

    @Test func hybrid_NaOHAtLiquidThreshold_ShowsNote() throws {
        let model = makeHybridModel(naohPercentage: 10)

        #expect(try noteRows(model).count == 1)
    }

    @Test func hybrid_NaOHAboveThreshold_NoNote() throws {
        let model = makeHybridModel(naohPercentage: 30)

        #expect(model.soapType == .cream)
        #expect(try noteRows(model).isEmpty)
    }

    @Test func singleNaOH_SolidSoap_NoNote() throws {
        let model = makeModel()

        #expect(model.soapType == .solid)
        #expect(try noteRows(model).isEmpty)
    }

    @Test func singleKOH_CreamSoapMethod_NoNote() throws {
        let model = makeModel()
        model.lyeType = "KOH"
        model.isCreamSoap = true

        #expect(try noteRows(model).isEmpty)
    }

    @Test func nonSoapRecipe_NoNote() throws {
        let model = makeModel()
        model.lyeType = "KOH"
        model.isNonSoapProduct = true

        let rows = model.calculatedAmountRows ?? []

        #expect(rows.allSatisfy { $0.note != LyeCalculator.liquidSoapDilutionNote })
    }
}
