import Testing
import Foundation
@testable import SoapWiz

/// The pure maths and rules behind the products a batch records (SW-348).
@Suite("BatchProduct")
struct BatchProductTests {

    private func estimate(
        size: Double,
        unit: String = "g",
        weight: Double,
        weightUnit: String = "g",
        batches: Int = 1
    ) -> Int? {
        BatchProduct.estimatedCount(
            size: size, unitSymbol: unit, oneBatchWeight: weight, weightUnit: weightUnit, batchCount: batches
        )
    }

    @Test func estimatedCount_TwoBatches_DoesNotCombineLeftovers() {
        #expect(estimate(size: 100, weight: 950, batches: 2) == 18)
    }

    @Test func estimatedCount_ExactDivision_DoesNotFloorDown() {
        #expect(estimate(size: 200, weight: 1000) == 5)
        #expect(estimate(size: 0.2, unit: "kg", weight: 1, weightUnit: "kg") == 5)
    }

    @Test func estimatedCount_OuncesRun_UsesOuncesForBothSides() {
        #expect(estimate(size: 4, unit: "oz", weight: 40, weightUnit: "oz") == 10)
        #expect(estimate(size: 4, unit: "oz", weight: 40, weightUnit: "oz", batches: 3) == 30)
    }

    @Test func estimatedCount_PoundsRun_UsesPoundsForBothSides() {
        #expect(estimate(size: 0.5, unit: "lb", weight: 3, weightUnit: "lb") == 6)
    }

    @Test func estimatedCount_MixedUnits_Converts() {
        #expect(estimate(size: 100, unit: "g", weight: 2, weightUnit: "kg") == 20)
        #expect(estimate(size: 1, unit: "oz", weight: 100, weightUnit: "g") == 3)
    }

    @Test func estimatedCount_SizeLargerThanBatch_ReturnsNil() {
        #expect(estimate(size: 1200, weight: 1000) == nil)
    }

    @Test func estimatedCount_ZeroOrUnknownWeight_ReturnsNil() {
        #expect(estimate(size: 100, weight: 0) == nil)
        #expect(estimate(size: 100, weight: -5) == nil)
        #expect(estimate(size: 100, weight: 1000, weightUnit: "") == nil)
        #expect(estimate(size: 100, weight: 1000, weightUnit: "ml") == nil)
    }

    @Test func estimatedCount_ZeroSizeOrNoBatches_ReturnsNil() {
        #expect(estimate(size: 0, weight: 1000) == nil)
        #expect(estimate(size: 100, weight: 1000, batches: 0) == nil)
    }

    @Test func estimatedCount_Parts_MultipliesByBatchCount() {
        #expect(estimate(size: 14, unit: "parts of batch", weight: 0, batches: 2) == 28)
    }

    @Test func estimatedCount_InvalidParts_ReturnsNil() {
        #expect(estimate(size: 1, unit: "parts of batch", weight: 1000) == nil)
        #expect(estimate(size: 2.5, unit: "parts of batch", weight: 1000) == nil)
    }

    @Test func estimatedCount_WholeBatchOrUnknownUnit_ReturnsNil() {
        #expect(estimate(size: 1, unit: "whole batch", weight: 1000) == nil)
        #expect(estimate(size: 1, unit: "bars", weight: 1000) == nil)
    }

    @Test func isValid_MassUnitWithSizeAndCount_IsTrue() {
        #expect(BatchProduct.isValid(size: 100, unitSymbol: "g", count: 18))
        #expect(BatchProduct.isValid(size: 0.5, unitSymbol: "lb", count: 1))
    }

    @Test func isValid_PartsMustBeWholeAndAtLeastTwo() {
        #expect(BatchProduct.isValid(size: 4, unitSymbol: "parts of batch", count: 4))
        #expect(BatchProduct.isValid(size: 1, unitSymbol: "parts of batch", count: 4) == false)
        #expect(BatchProduct.isValid(size: 2.5, unitSymbol: "parts of batch", count: 4) == false)
    }

    @Test func isValid_BadSizeCountOrUnit_IsFalse() {
        #expect(BatchProduct.isValid(size: 0, unitSymbol: "g", count: 3) == false)
        #expect(BatchProduct.isValid(size: -1, unitSymbol: "g", count: 3) == false)
        #expect(BatchProduct.isValid(size: .infinity, unitSymbol: "g", count: 3) == false)
        #expect(BatchProduct.isValid(size: 100, unitSymbol: "g", count: 0) == false)
        #expect(BatchProduct.isValid(size: 1, unitSymbol: "whole batch", count: 1) == false)
        #expect(BatchProduct.isValid(size: 100, unitSymbol: "ml", count: 1) == false)
    }

    @Test func label_MassUnit_ShowsSizeAndSymbol() {
        let expected = "\(Double(100).formatted(.number.precision(.fractionLength(0...2)))) g"
        #expect(BatchProduct.label(size: 100, unitSymbol: "g") == expected)
    }

    @Test func label_Parts_SaysParts() {
        let expected = "\(Double(14).formatted(.number.precision(.fractionLength(0...2)))) parts"
        #expect(BatchProduct.label(size: 14, unitSymbol: "parts of batch") == expected)
    }

    @Test func quantityLabel_JoinsSizeAndCount() {
        let product = BatchProduct(size: 100, unitSymbol: "g", count: 18)

        #expect(product.quantityLabel == "\(BatchProduct.label(size: 100, unitSymbol: "g")) × 18")
        #expect(BatchProduct.quantityLabel(size: 100, unitSymbol: "g", count: 18) == product.quantityLabel)
    }

    @Test func isSeparateFromBatch_FollowsTheRecipeSizeRule() {
        #expect(ProductUnit.isSeparateFromBatch(size: 1, unitSymbol: "whole batch") == false)
        #expect(ProductUnit.isSeparateFromBatch(size: 1, unitSymbol: "parts of batch") == false)
        #expect(ProductUnit.isSeparateFromBatch(size: 2, unitSymbol: "parts of batch"))
        #expect(ProductUnit.isSeparateFromBatch(size: 100, unitSymbol: "g"))
    }
}
