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
