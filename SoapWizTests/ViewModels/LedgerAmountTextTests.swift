import Testing
@testable import SoapWiz

@Suite("Ledger amount text")
struct LedgerAmountTextTests {

    @Test func init_BarePercent_JoinsNumberWithNoDetail() {
        let sut = LedgerAmountText(number: "72", unit: "%")

        #expect(sut.figure == "72%")
        #expect(sut.detail == "")
    }

    @Test func init_PercentWithWeight_AddsWeightAfterMiddleDot() {
        let sut = LedgerAmountText(number: "72", unit: "%", convertedWeight: "360 g")

        #expect(sut.figure == "72%")
        #expect(sut.detail == " · 360 g")
    }

    @Test func init_PercentOfOils_JoinsSignAndKeepsQualifier() {
        let sut = LedgerAmountText(number: "3", unit: "% of oils", convertedWeight: "15 g")

        #expect(sut.figure == "3%")
        #expect(sut.detail == " of oils · 15 g")
    }

    @Test func init_WeightUnit_FollowsNumberAfterSpace() {
        let sut = LedgerAmountText(number: "360", unit: "g")

        #expect(sut.figure == "360")
        #expect(sut.detail == " g")
    }

    @Test func init_EmptyUnit_HasNoDetail() {
        let sut = LedgerAmountText(number: "2", unit: "")

        #expect(sut.figure == "2")
        #expect(sut.detail == "")
    }

    @Test func init_EmptyUnitWithWeight_StartsDetailAtMiddleDot() {
        let sut = LedgerAmountText(number: "2", unit: "", convertedWeight: "40 g")

        #expect(sut.detail == " · 40 g")
    }
}

@Suite("Cost breakdown caption")
struct CostBreakdownCaptionTests {

    @Test(arguments: [(1, "one of one"), (5, "one of five"), (9, "one of nine")])
    func sizesPerBatch_BelowTen_SpellsOutNumber(count: Int, expected: String) {
        #expect(CostBreakdownCaption.sizesPerBatch(count) == expected)
    }

    @Test(arguments: [10, 47])
    func sizesPerBatch_TenOrMore_UsesDigits(count: Int) {
        #expect(CostBreakdownCaption.sizesPerBatch(count) == "one of \(count)")
    }
}

@Suite("Product cost breakdown – sizes per batch")
struct ProductCostBreakdownSizesPerBatchTests {

    @Test func sizesPerBatch_NoShare_ReturnsNil() {
        #expect(ProductCostBreakdown().sizesPerBatch == nil)
    }

    @Test func sizesPerBatch_ZeroShare_ReturnsNil() {
        #expect(ProductCostBreakdown(batchShare: 0).sizesPerBatch == nil)
    }

    @Test func sizesPerBatch_ExactDivision_DoesNotLoseOneToRounding() {
        // 1 / 0.2 is 4.999… in floating point.
        #expect(ProductCostBreakdown(batchShare: 0.2).sizesPerBatch == 5)
    }

    @Test func sizesPerBatch_Remainder_RoundsDownToWholeProducts() {
        #expect(ProductCostBreakdown(batchShare: 0.15).sizesPerBatch == 6)
    }

    @Test func sizesPerBatch_WholeBatch_ReturnsOne() {
        #expect(ProductCostBreakdown(batchShare: 1).sizesPerBatch == 1)
    }

    @Test func sizesPerBatch_LargerThanBatch_ReturnsNil() {
        #expect(ProductCostBreakdown(batchShare: 1.5).sizesPerBatch == nil)
    }
}
