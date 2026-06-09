import Testing
import Foundation
@testable import SoapWiz

@Suite("MassUnitConverter")
struct MassUnitConverterTests {

    @Test func convert_SameUnit_ReturnsAmountUnchanged() {
        #expect(MassUnitConverter.convert(5, from: "g", to: "g") == 5)
    }

    @Test func convert_KilogramsToGrams() throws {
        let result = try #require(MassUnitConverter.convert(1, from: "kg", to: "g"))
        #expect(abs(result - 1000) < 1e-9)
    }

    @Test func convert_GramsToKilograms() throws {
        let result = try #require(MassUnitConverter.convert(1000, from: "g", to: "kg"))
        #expect(abs(result - 1) < 1e-9)
    }

    @Test func convert_OuncesToGrams() throws {
        let result = try #require(MassUnitConverter.convert(1, from: "oz", to: "g"))
        // 1 oz ≈ 28.3495 g — Foundation's coefficient is precise to well under a milligram.
        #expect(abs(result - 28.3495) < 0.001)
    }

    @Test func convert_PoundsToGrams() throws {
        let result = try #require(MassUnitConverter.convert(1, from: "lb", to: "g"))
        // 1 lb ≈ 453.592 g.
        #expect(abs(result - 453.592) < 0.01)
    }

    @Test func convert_RoundTrip_PreservesValue() throws {
        let toOz = try #require(MassUnitConverter.convert(500, from: "g", to: "oz"))
        let back = try #require(MassUnitConverter.convert(toOz, from: "oz", to: "g"))
        #expect(abs(back - 500) < 1e-9)
    }

    @Test func convert_VolumeUnit_ReturnsNil() {
        #expect(MassUnitConverter.convert(1, from: "ml", to: "g") == nil)
        #expect(MassUnitConverter.convert(1, from: "L", to: "kg") == nil)
    }

    @Test func convert_PercentageUnit_ReturnsNil() {
        #expect(MassUnitConverter.convert(1, from: "% of oils", to: "g") == nil)
        #expect(MassUnitConverter.convert(1, from: "g", to: "%") == nil)
    }

    @Test func isMass_MassUnits_True() {
        #expect(MassUnitConverter.isMass("g"))
        #expect(MassUnitConverter.isMass("kg"))
        #expect(MassUnitConverter.isMass("oz"))
        #expect(MassUnitConverter.isMass("lb"))
    }

    @Test func isMass_NonMassUnits_False() {
        #expect(MassUnitConverter.isMass("ml") == false)
        #expect(MassUnitConverter.isMass("L") == false)
        #expect(MassUnitConverter.isMass("% of oils") == false)
        #expect(MassUnitConverter.isMass("") == false)
    }
}

@Suite("IngredientUnitConverter")
struct IngredientUnitConverterTests {

    @Test func convert_MillilitersToGrams_CustomDensity() throws {
        let result = try #require(IngredientUnitConverter.convert(100, from: "ml", to: "g", density: 0.911))
        #expect(abs(result.value - 91.1) < 1e-9)
        #expect(result.density == 0.911)
        #expect(result.usedDefaultDensity == false)
    }

    @Test func convert_LitersToKilograms_CustomDensity() throws {
        // g/mL = kg/L, so 1.2 L at 0.92 → 1.104 kg.
        let result = try #require(IngredientUnitConverter.convert(1.2, from: "L", to: "kg", density: 0.92))
        #expect(abs(result.value - 1.104) < 1e-9)
        #expect(result.density == 0.92)
        #expect(result.usedDefaultDensity == false)
    }

    @Test func convert_VolumeToMass_NilDensity_FallsBackToDefault() throws {
        let result = try #require(IngredientUnitConverter.convert(100, from: "ml", to: "g", density: nil))
        #expect(abs(result.value - 92) < 1e-9)
        #expect(result.density == IngredientUnitConverter.defaultDensity)
        #expect(result.usedDefaultDensity)
    }

    @Test func convert_MassToVolume_DividesByDensity() throws {
        // 92 g at 0.92 g/mL → 100 mL.
        let result = try #require(IngredientUnitConverter.convert(92, from: "g", to: "ml", density: 0.92))
        #expect(abs(result.value - 100) < 1e-9)
        #expect(result.density == 0.92)
        #expect(result.usedDefaultDensity == false)
    }

    @Test func convert_VolumeToMass_CrossUnit_LitersToGrams() throws {
        // 1 L at 0.92 → 1000 mL → 920 g.
        let result = try #require(IngredientUnitConverter.convert(1, from: "L", to: "g", density: 0.92))
        #expect(abs(result.value - 920) < 1e-9)
    }

    @Test func convert_MassUnits_IgnoreDensity() throws {
        let result = try #require(IngredientUnitConverter.convert(1, from: "kg", to: "g", density: 0.5))
        #expect(abs(result.value - 1000) < 1e-9)
        #expect(result.density == nil)
        #expect(result.usedDefaultDensity == false)
    }

    @Test func convert_SameMassUnit_ReturnsUnchanged() throws {
        let result = try #require(IngredientUnitConverter.convert(5, from: "g", to: "g", density: nil))
        #expect(result.value == 5)
        #expect(result.density == nil)
    }

    @Test func convert_VolumeToVolume_IgnoresDensity() throws {
        let result = try #require(IngredientUnitConverter.convert(2, from: "L", to: "ml", density: 0.5))
        #expect(abs(result.value - 2000) < 1e-9)
        #expect(result.density == nil)
        #expect(result.usedDefaultDensity == false)
    }

    @Test func convert_RoundTrip_VolumeMassVolume_PreservesValue() throws {
        let toGrams = try #require(IngredientUnitConverter.convert(250, from: "ml", to: "g", density: 0.88))
        let back = try #require(IngredientUnitConverter.convert(toGrams.value, from: "g", to: "ml", density: 0.88))
        #expect(abs(back.value - 250) < 1e-9)
    }

    @Test func convert_ZeroDensity_ReturnsNil() {
        // Would otherwise divide by zero (mass→volume) or yield zero mass (volume→mass).
        #expect(IngredientUnitConverter.convert(100, from: "g", to: "ml", density: 0) == nil)
        #expect(IngredientUnitConverter.convert(100, from: "ml", to: "g", density: 0) == nil)
    }

    @Test func convert_NegativeDensity_ReturnsNil() {
        #expect(IngredientUnitConverter.convert(100, from: "ml", to: "g", density: -0.5) == nil)
    }

    @Test func convert_UnknownUnit_ReturnsNil() {
        #expect(IngredientUnitConverter.convert(1, from: "un", to: "g", density: 0.92) == nil)
        #expect(IngredientUnitConverter.convert(1, from: "% of oils", to: "g", density: 0.92) == nil)
        #expect(IngredientUnitConverter.convert(1, from: "g", to: "un", density: 0.92) == nil)
    }

    @Test func isVolume_VolumeUnits_True() {
        #expect(IngredientUnitConverter.isVolume("ml"))
        #expect(IngredientUnitConverter.isVolume("L"))
    }

    @Test func isVolume_NonVolumeUnits_False() {
        #expect(IngredientUnitConverter.isVolume("g") == false)
        #expect(IngredientUnitConverter.isVolume("kg") == false)
        #expect(IngredientUnitConverter.isVolume("un") == false)
        #expect(IngredientUnitConverter.isVolume("") == false)
    }
}
