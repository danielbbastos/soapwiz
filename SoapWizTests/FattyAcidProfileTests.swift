import Testing
@testable import SoapWiz

@Suite
struct FattyAcidProfileTests {

    @Test func hardness_SumsSaturatedAcids() {
        var p = FattyAcidProfile()
        p.lauric = 48; p.myristic = 19; p.palmitic = 9; p.stearic = 3
        #expect(p.hardness == 79)
    }

    @Test func cleansing_OnlyLauricAndMyristic() {
        var p = FattyAcidProfile()
        p.lauric = 48; p.myristic = 19; p.palmitic = 9; p.stearic = 3; p.oleic = 6
        #expect(p.cleansing == 67)
    }

    @Test func conditioning_SumsUnsaturatedAndRicinoleic() {
        var p = FattyAcidProfile()
        p.oleic = 60; p.linoleic = 20; p.linolenic = 5; p.ricinoleic = 10
        #expect(p.conditioning == 95)
    }

    @Test func bubbly_LauricMyristicRicinoleic() {
        var p = FattyAcidProfile()
        p.lauric = 5; p.myristic = 3; p.ricinoleic = 90
        #expect(p.bubbly == 98)
    }

    @Test func creamy_PalmiticStearicRicinoleic() {
        var p = FattyAcidProfile()
        p.palmitic = 10; p.stearic = 5; p.ricinoleic = 90
        #expect(p.creamy == 105)
    }

    @Test func longevity_PalmiticAndStearic() {
        var p = FattyAcidProfile()
        p.palmitic = 14; p.stearic = 3
        #expect(p.longevity == 17)
    }

    @Test func iodineValue_AppliesPerAcidConstants() {
        var p = FattyAcidProfile()
        p.oleic = 69
        p.linoleic = 12
        p.linolenic = 1
        let oleicContribution: Double = 69 * 90
        let linoleicContribution: Double = 12 * 181
        let linolenicContribution: Double = 1 * 273
        let expected: Double = (oleicContribution + linoleicContribution + linolenicContribution) / 100
        #expect(p.iodineValue == expected)
    }

    @Test func iodineValue_AllSaturated_IsZero() {
        var p = FattyAcidProfile()
        p.lauric = 50; p.myristic = 20; p.palmitic = 20; p.stearic = 10
        #expect(p.iodineValue == 0)
    }

    @Test func saturatedTotals_IncludeAllFourSaturated() {
        var p = FattyAcidProfile()
        p.lauric = 1; p.myristic = 2; p.palmitic = 3; p.stearic = 4; p.oleic = 5; p.ricinoleic = 6
        #expect(p.saturated == 10)
        #expect(p.monoUnsaturated == 5)
    }

    @Test func weightedSum_EmptyContributions_ReturnsZero() {
        let result = FattyAcidProfile.weightedSum([])
        #expect(result == .zero)
    }

    @Test func weightedSum_ZeroWeights_ReturnsZero() {
        var p = FattyAcidProfile()
        p.oleic = 60
        let result = FattyAcidProfile.weightedSum([(p, 0), (p, 0)])
        #expect(result == .zero)
    }

    @Test func weightedSum_EqualWeights_AveragesProfiles() {
        var a = FattyAcidProfile(); a.palmitic = 10; a.oleic = 70
        var b = FattyAcidProfile(); b.palmitic = 30; b.oleic = 50
        let result = FattyAcidProfile.weightedSum([(a, 50), (b, 50)])
        #expect(result.palmitic == 20)
        #expect(result.oleic == 60)
    }

    @Test func weightedSum_UnevenWeights_AppliesShares() {
        var coconut = FattyAcidProfile(); coconut.lauric = 48; coconut.myristic = 19; coconut.oleic = 6
        var olive = FattyAcidProfile(); olive.palmitic = 14; olive.oleic = 69
        let result = FattyAcidProfile.weightedSum([(coconut, 30), (olive, 70)])
        #expect(abs(result.lauric - 14.4) < 0.001)
        #expect(abs(result.palmitic - 9.8) < 0.001)
        #expect(abs(result.oleic - (6 * 0.3 + 69 * 0.7)) < 0.001)
    }

    @Test func ins_AppliesMcDanielFormula() {
        var olive = FattyAcidProfile()
        olive.palmitic = 14; olive.stearic = 3; olive.oleic = 69; olive.linoleic = 12; olive.linolenic = 1
        let ins = FattyAcidProfile.ins(naOHSapFactor: 0.134, iodineValue: olive.iodineValue)
        let sapKOH = 0.134 * 1402.5
        #expect(abs(ins - (sapKOH - olive.iodineValue)) < 0.0001)
    }
}
