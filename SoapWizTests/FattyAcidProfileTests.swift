import Testing
@testable import SoapWiz

@Suite
struct FattyAcidProfileTests {

    @Test func hardness_SumsSaturatedAcids() {
        var profile = FattyAcidProfile()
        profile.lauric = 48; profile.myristic = 19; profile.palmitic = 9; profile.stearic = 3
        #expect(profile.hardness == 79)
    }

    @Test func cleansing_OnlyLauricAndMyristic() {
        var profile = FattyAcidProfile()
        profile.lauric = 48; profile.myristic = 19; profile.palmitic = 9; profile.stearic = 3; profile.oleic = 6
        #expect(profile.cleansing == 67)
    }

    @Test func conditioning_SumsUnsaturatedAndRicinoleic() {
        var profile = FattyAcidProfile()
        profile.oleic = 60; profile.linoleic = 20; profile.linolenic = 5; profile.ricinoleic = 10
        #expect(profile.conditioning == 95)
    }

    @Test func bubbly_LauricMyristicRicinoleic() {
        var profile = FattyAcidProfile()
        profile.lauric = 5; profile.myristic = 3; profile.ricinoleic = 90
        #expect(profile.bubbly == 98)
    }

    @Test func creamy_PalmiticStearicRicinoleic() {
        var profile = FattyAcidProfile()
        profile.palmitic = 10; profile.stearic = 5; profile.ricinoleic = 90
        #expect(profile.creamy == 105)
    }

    @Test func longevity_PalmiticAndStearic() {
        var profile = FattyAcidProfile()
        profile.palmitic = 14; profile.stearic = 3
        #expect(profile.longevity == 17)
    }

    @Test func iodineValue_AppliesPerAcidConstants() {
        var profile = FattyAcidProfile()
        profile.oleic = 69
        profile.linoleic = 12
        profile.linolenic = 1
        let oleicContribution: Double = 69 * 90
        let linoleicContribution: Double = 12 * 181
        let linolenicContribution: Double = 1 * 273
        let expected: Double = (oleicContribution + linoleicContribution + linolenicContribution) / 100
        #expect(profile.iodineValue == expected)
    }

    @Test func iodineValue_AllSaturated_IsZero() {
        var profile = FattyAcidProfile()
        profile.lauric = 50; profile.myristic = 20; profile.palmitic = 20; profile.stearic = 10
        #expect(profile.iodineValue == 0)
    }

    @Test func saturatedTotals_IncludeAllFourSaturated() {
        var profile = FattyAcidProfile()
        profile.lauric = 1; profile.myristic = 2; profile.palmitic = 3; profile.stearic = 4; profile.oleic = 5; profile.ricinoleic = 6
        #expect(profile.saturated == 10)
        #expect(profile.monoUnsaturated == 5)
    }

    @Test func weightedSum_EmptyContributions_ReturnsZero() {
        let result = FattyAcidProfile.weightedSum([])
        #expect(result == .zero)
    }

    @Test func weightedSum_ZeroWeights_ReturnsZero() {
        var profile = FattyAcidProfile()
        profile.oleic = 60
        let result = FattyAcidProfile.weightedSum([(profile, 0), (profile, 0)])
        #expect(result == .zero)
    }

    @Test func weightedSum_EqualWeights_AveragesProfiles() {
        var profileA = FattyAcidProfile(); profileA.palmitic = 10; profileA.oleic = 70
        var profileB = FattyAcidProfile(); profileB.palmitic = 30; profileB.oleic = 50
        let result = FattyAcidProfile.weightedSum([(profileA, 50), (profileB, 50)])
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
