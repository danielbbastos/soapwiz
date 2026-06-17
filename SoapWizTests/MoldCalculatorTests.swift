import Testing
import Foundation
@testable import SoapWiz

@Suite
struct MoldCalculatorTests {

    // MARK: - Volume

    @Test func volume_Rectangular_MultipliesDimensions() {
        let dims = MoldDimensions(length: 20, width: 8, depth: 6)
        #expect(MoldCalculator.volume(shape: .rectangular, dimensions: dims) == 960)
    }

    @Test func volume_Cylindrical_UsesPiDSquaredDepthOverFour() {
        let dims = MoldDimensions(diameter: 10, depth: 20)
        let expected = Double.pi * 10 * 10 * 20 / 4
        #expect(MoldCalculator.volume(shape: .cylindrical, dimensions: dims) == expected)
    }

    @Test func volume_Rectangular_IgnoresCylinderFields() {
        let dims = MoldDimensions(length: 10, width: 5, diameter: 99, depth: 4)
        #expect(MoldCalculator.volume(shape: .rectangular, dimensions: dims) == 200)
    }

    @Test func volume_ZeroDimension_ReturnsZero() {
        let dims = MoldDimensions(length: 20, width: 0, depth: 6)
        #expect(MoldCalculator.volume(shape: .rectangular, dimensions: dims) == 0)
    }

    // MARK: - Fill factors

    @Test func factor_StandardCentimeters_Is070() {
        #expect(MoldCalculator.factor(for: .centimeters, fillMode: .standard) == 0.70)
    }

    @Test func factor_StandardInches_Is040() {
        #expect(MoldCalculator.factor(for: .inches, fillMode: .standard) == 0.40)
    }

    @Test func factor_ExtraHeadroomCentimeters_Is065() {
        #expect(MoldCalculator.factor(for: .centimeters, fillMode: .extraHeadroom) == 0.65)
    }

    @Test func factor_ExtraHeadroomInches_Is037() {
        #expect(MoldCalculator.factor(for: .inches, fillMode: .extraHeadroom) == 0.37)
    }

    @Test func factor_ExtraHeadroom_IsLessThanStandard() {
        #expect(MoldCalculator.factor(for: .centimeters, fillMode: .extraHeadroom)
                < MoldCalculator.factor(for: .centimeters, fillMode: .standard))
        #expect(MoldCalculator.factor(for: .inches, fillMode: .extraHeadroom)
                < MoldCalculator.factor(for: .inches, fillMode: .standard))
    }

    // MARK: - Oil weight (natural unit)

    @Test func oilWeight_GramsStandard_VolumeTimesFactor() {
        let dims = MoldDimensions(length: 20, width: 8, depth: 6) // 960 cm³
        let result = MoldCalculator.oilWeight(
            shape: .rectangular, dimensions: dims, lengthUnit: .centimeters, fillMode: .standard
        )
        #expect(result == 960 * 0.70)
    }

    @Test func oilWeight_OuncesStandard_VolumeTimesFactor() {
        let dims = MoldDimensions(length: 8, width: 3.5, depth: 2.5) // 70 in³
        let result = MoldCalculator.oilWeight(
            shape: .rectangular, dimensions: dims, lengthUnit: .inches, fillMode: .standard
        )
        #expect(result == 70 * 0.40)
    }

    @Test func oilWeight_ExtraHeadroom_IsLessThanStandard() {
        let dims = MoldDimensions(length: 20, width: 8, depth: 6)
        let standard = MoldCalculator.oilWeight(
            shape: .rectangular, dimensions: dims, lengthUnit: .centimeters, fillMode: .standard
        )
        let extra = MoldCalculator.oilWeight(
            shape: .rectangular, dimensions: dims, lengthUnit: .centimeters, fillMode: .extraHeadroom
        )
        #expect(extra < standard)
    }

    // MARK: - Oil weight (converted to target unit)

    @Test func oilWeightInTarget_SameAsNatural_Unchanged() throws {
        let dims = MoldDimensions(length: 20, width: 8, depth: 6)
        let result = try #require(MoldCalculator.oilWeight(
            shape: .rectangular, dimensions: dims,
            lengthUnit: .centimeters, fillMode: .standard, in: "g"
        ))
        #expect(result == 960 * 0.70)
    }

    @Test func oilWeightInTarget_GramsToKilograms_Converts() throws {
        let dims = MoldDimensions(length: 20, width: 8, depth: 6) // 960 cm³ → 672 g
        let result = try #require(MoldCalculator.oilWeight(
            shape: .rectangular, dimensions: dims,
            lengthUnit: .centimeters, fillMode: .standard, in: "kg"
        ))
        let expected = try #require(MassUnitConverter.convert(672, from: "g", to: "kg"))
        #expect(result == expected)
    }

    @Test func oilWeightInTarget_OuncesToGrams_Converts() throws {
        let dims = MoldDimensions(length: 8, width: 3.5, depth: 2.5) // 70 in³ → 28 oz
        let result = try #require(MoldCalculator.oilWeight(
            shape: .rectangular, dimensions: dims,
            lengthUnit: .inches, fillMode: .standard, in: "g"
        ))
        let expected = try #require(MassUnitConverter.convert(28, from: "oz", to: "g"))
        #expect(result == expected)
    }

    @Test func oilWeightInTarget_NonMassUnit_ReturnsNil() {
        let dims = MoldDimensions(length: 20, width: 8, depth: 6)
        #expect(MoldCalculator.oilWeight(
            shape: .rectangular, dimensions: dims,
            lengthUnit: .centimeters, fillMode: .standard, in: "ml"
        ) == nil)
    }
}
