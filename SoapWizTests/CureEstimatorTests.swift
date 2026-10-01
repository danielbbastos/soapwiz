import Testing
import Foundation
@testable import SoapWiz

@Suite("Cure estimator")
struct CureEstimatorTests {

    /// Olive 11/3 and coconut 47/19/9/3, as the ingredient library has them.
    private static let olive = FattyAcidProfile.mock(palmitic: 11, stearic: 3, oleic: 75, linoleic: 10)
    private static let coconut = FattyAcidProfile.mock(lauric: 47, myristic: 19, palmitic: 9, stearic: 3, oleic: 7)

    private static func blend(olive oliveShare: Double) -> FattyAcidProfile {
        FattyAcidProfile.weightedSum([(olive, oliveShare), (coconut, 1 - oliveShare)])
    }

    private func estimate(
        _ profile: FattyAcidProfile,
        process: SoapProcess = .cold,
        makesSoap: Bool = true,
        soapType: SoapType = .solid
    ) -> CureEstimate? {
        CureEstimator.estimate(makesSoap: makesSoap, soapType: soapType, fattyAcidProfile: profile, process: process)
    }

    @Test func estimate_NonSoapRecipe_ReturnsNil() {
        #expect(estimate(Self.blend(olive: 0.5), makesSoap: false) == nil)
    }

    @Test(arguments: [SoapType.liquid, .cream])
    func estimate_SoapThatIsNotABar_ReturnsNil(_ soapType: SoapType) {
        #expect(estimate(Self.blend(olive: 0.5), soapType: soapType) == nil)
    }

    @Test func estimate_TypicalColdProcessBar_IsFourToSixWeeks() throws {
        let result = try #require(estimate(Self.blend(olive: 0.5)))
        #expect(result.band == .typicalCold)
        #expect(result.weeks == 4...6)
        #expect(result.defaultDays == 42)
    }

    @Test func estimate_TypicalHotProcessBar_IsTwoToFourWeeks() throws {
        let result = try #require(estimate(Self.blend(olive: 0.5), process: .hot))
        #expect(result.band == .typicalHot)
        #expect(result.defaultDays == 28)
    }

    @Test func estimate_BastileEightyTwenty_IsHighOlive() throws {
        let result = try #require(estimate(Self.blend(olive: 0.8)))
        #expect(result.band == .highOlive)
        #expect(result.weeks == 6...8)
    }

    @Test func estimate_PureOlive_IsCastile() throws {
        let result = try #require(estimate(Self.olive))
        #expect(result.band == .castile)
        #expect(result.weeks == 6...26)
        #expect(result.defaultDays == 182)
    }

    @Test(arguments: [0.8, 1.0])
    func estimate_SoftBlendHotProcessed_KeepsItsBand(_ oliveShare: Double) {
        let profile = Self.blend(olive: oliveShare)
        #expect(estimate(profile, process: .hot)?.band == estimate(profile, process: .cold)?.band)
    }

    // MARK: - Explanation

    /// Made hot, a soft blend says why the range didn't move.
    @Test(arguments: [0.8, 1.0])
    func explanation_SoftBlendHotProcessed_SaysCookingDoesNotShortenIt(_ oliveShare: Double) throws {
        let result = try #require(estimate(Self.blend(olive: oliveShare), process: .hot))
        #expect(result.explanation.hasPrefix(result.band.reason))
        #expect(result.explanation.contains("Hot process doesn't shorten this"))
    }

    @Test(arguments: [0.8, 1.0])
    func explanation_SoftBlendColdProcessed_IsTheReasonAlone(_ oliveShare: Double) throws {
        let result = try #require(estimate(Self.blend(olive: oliveShare), process: .cold))
        #expect(result.explanation == result.band.reason)
    }

    /// A typical bar's range already moves with the process: no note needed.
    @Test(arguments: [SoapProcess.cold, .hot])
    func explanation_TypicalBar_IsTheReasonAlone(_ process: SoapProcess) throws {
        let result = try #require(estimate(Self.blend(olive: 0.5), process: process))
        #expect(result.explanation == result.band.reason)
    }

    @Test func estimate_HardnessAtBottomOfRecommendedRange_IsTypical() throws {
        let profile = FattyAcidProfile.mock(palmitic: 29, oleic: 71)
        let result = try #require(estimate(profile))
        #expect(result.band == .typicalCold)
    }

    @Test func estimate_HardnessJustBelowRecommendedRange_IsHighOlive() throws {
        let profile = FattyAcidProfile.mock(palmitic: 28.9, oleic: 71.1)
        let result = try #require(estimate(profile))
        #expect(result.band == .highOlive)
    }

    @Test func estimate_HardnessAtCastileCutOff_IsHighOlive() throws {
        let profile = FattyAcidProfile.mock(palmitic: 20, oleic: 80)
        let result = try #require(estimate(profile))
        #expect(result.band == .highOlive)
    }

    /// No fatty acid data reads as zero hardness, which must not pass for castile.
    @Test(arguments: [SoapProcess.cold, .hot])
    func estimate_NoFattyAcidData_FallsBackToTypical(_ process: SoapProcess) throws {
        let result = try #require(estimate(.zero, process: process))
        #expect(result.band == (process == .cold ? .typicalCold : .typicalHot))
    }
}

extension FattyAcidProfile {
    static func mock(
        lauric: Double = 0,
        myristic: Double = 0,
        palmitic: Double = 0,
        stearic: Double = 0,
        oleic: Double = 0,
        linoleic: Double = 0
    ) -> FattyAcidProfile {
        var profile = FattyAcidProfile()
        profile.lauric = lauric
        profile.myristic = myristic
        profile.palmitic = palmitic
        profile.stearic = stearic
        profile.oleic = oleic
        profile.linoleic = linoleic
        return profile
    }
}
