import Testing
@testable import SoapWiz

@Suite("SoapPropertyRow")
struct SoapPropertyRowTests {

    @Test func rangeText_WholeBounds_JoinsWithTo() {
        #expect(SoapPropertyIndicatorView.rangeText(29...54) == "29 to 54")
    }

    @Test func rangeText_HasNoDashes() {
        let text = SoapPropertyIndicatorView.rangeText(29...54)
        #expect(!text.contains("\u{2013}"))
        #expect(!text.contains("\u{2014}"))
    }

    @Test func rangeText_FractionalBounds_RoundsToWholeNumbers() {
        #expect(SoapPropertyIndicatorView.rangeText(136.4...169.6) == "136 to 170")
    }

    @Test func fraction_Midpoint_IsHalf() {
        #expect(SoapPropertyRowView.fraction(of: 50, in: 0...100) == 0.5)
    }

    @Test func fraction_BelowScale_ClampsToZero() {
        #expect(SoapPropertyRowView.fraction(of: -10, in: 0...100) == 0)
    }

    @Test func fraction_AboveScale_ClampsToOne() {
        #expect(SoapPropertyRowView.fraction(of: 400, in: 0...320) == 1)
    }

    @Test func fraction_NonZeroLowerBound_IsRelativeToLowerBound() {
        #expect(SoapPropertyRowView.fraction(of: 125, in: 100...200) == 0.25)
        #expect(SoapPropertyRowView.fraction(of: 100, in: 100...200) == 0)
    }

    @Test func fraction_ZeroWidthScale_ReturnsZero() {
        let result = SoapPropertyRowView.fraction(of: 5, in: 5...5)
        #expect(result == 0)
        #expect(!result.isNaN)
    }

    @Test func isEffectivelyZero_Zero_IsTrue() {
        #expect(FattyAcidRow.isEffectivelyZero(0))
    }

    @Test func isEffectivelyZero_RoundsDownToZero_IsTrue() {
        #expect(FattyAcidRow.isEffectivelyZero(0.04))
        #expect(FattyAcidRow.isEffectivelyZero(-0.04))
    }

    @Test func isEffectivelyZero_RoundsUpToTenth_IsFalse() {
        #expect(!FattyAcidRow.isEffectivelyZero(0.05))
    }

    @Test func isEffectivelyZero_OrdinaryValue_IsFalse() {
        #expect(!FattyAcidRow.isEffectivelyZero(21))
    }
}
