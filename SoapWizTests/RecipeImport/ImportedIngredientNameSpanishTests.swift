import Testing
import Foundation
@testable import SoapWiz

@Suite("Imported ingredient names, Spanish lye and water")
struct ImportedIngredientNameSpanishTests {

    @Test(arguments: [
        "sosa", "Sosa cáustica", "sosa caustica", "SOSA CÁUSTICA", "soda cáustica", "soda caustica",
        "Hidróxido de sodio", "hidroxido de sodio", "soda", "Soda", "soda (NaOH)"
    ])
    func lyeType_SpanishSodium_IsNaOH(_ name: String) {
        #expect(ImportedIngredientName.lyeType(ofLye: name) == "NaOH")
        #expect(ImportedIngredientName.isLye(name))
    }

    @Test(arguments: ["potasa", "Potasa cáustica", "potasa caustica", "Hidróxido de potasio", "hidroxido de potasio"])
    func lyeType_SpanishPotassium_IsKOH(_ name: String) {
        #expect(ImportedIngredientName.lyeType(ofLye: name) == "KOH")
        #expect(ImportedIngredientName.isLye(name))
    }

    @Test(arguments: ["baking soda", "Soda Ash", "bicarbonate of soda", "sodium lactate", "soda water"])
    func lyeType_OtherSodaIngredients_AreNotLyes(_ name: String) {
        #expect(ImportedIngredientName.lyeType(ofLye: name) == nil)
        #expect(!ImportedIngredientName.isLye(name))
    }

    @Test(arguments: ["agua", "Agua", "agua destilada", "Agua desmineralizada", "agua (destilada)"])
    func isWater_SpanishWater_IsWater(_ name: String) {
        #expect(ImportedIngredientName.isWater(name))
    }

    @Test(arguments: ["agua de rosas", "aguacate"])
    func isWater_OtherAguaNames_AreNotWater(_ name: String) {
        #expect(!ImportedIngredientName.isWater(name))
    }
}
