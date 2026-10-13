import Testing
@testable import SoapWiz

@Suite("SoapQuality")
struct SoapQualityTests {

    @Test(arguments: SoapQuality.allCases)
    func explanation_IsNotEmpty(quality: SoapQuality) {
        #expect(!quality.explanation.isEmpty)
    }

    @Test(arguments: SoapQuality.allCases)
    func explanation_HasNoDashes(quality: SoapQuality) {
        #expect(!quality.explanation.contains("\u{2014}"))
        #expect(!quality.explanation.contains("\u{2013}"))
    }

    @Test(arguments: SoapQuality.allCases)
    func explanation_StatesTheRecommendedRange(quality: SoapQuality) {
        let low = Int(quality.recommendedRange.lowerBound)
        let high = Int(quality.recommendedRange.upperBound)
        #expect(quality.explanation.contains("\(low) to \(high)"))
    }
}
