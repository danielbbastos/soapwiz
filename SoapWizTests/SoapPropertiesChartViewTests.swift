import Testing
import CoreGraphics
@testable import SoapWiz

@Suite
struct SoapPropertiesChartViewTests {

    @Test func showsFullNames_ZeroPlotWidth_ReturnsFalse() {
        #expect(!SoapPropertiesChartView.showsFullNames(plotWidth: 0, fullNameWidth: 92, count: 6, gap: 8))
    }

    @Test func showsFullNames_ZeroFullNameWidth_ReturnsFalse() {
        #expect(!SoapPropertiesChartView.showsFullNames(plotWidth: 600, fullNameWidth: 0, count: 6, gap: 8))
    }

    @Test func showsFullNames_ZeroCount_ReturnsFalse() {
        #expect(!SoapPropertiesChartView.showsFullNames(plotWidth: 600, fullNameWidth: 92, count: 0, gap: 8))
    }

    @Test func showsFullNames_ExactlyAtThreshold_ReturnsTrue() {
        #expect(SoapPropertiesChartView.showsFullNames(plotWidth: 600, fullNameWidth: 92, count: 6, gap: 8))
    }

    @Test func showsFullNames_JustBelowThreshold_ReturnsFalse() {
        #expect(!SoapPropertiesChartView.showsFullNames(plotWidth: 599.9, fullNameWidth: 92, count: 6, gap: 8))
    }

    @Test func showsFullNames_ComfortablyWide_ReturnsTrue() {
        #expect(SoapPropertiesChartView.showsFullNames(plotWidth: 900, fullNameWidth: 92, count: 6, gap: 8))
    }

    @Test func showsFullNames_Narrow_ReturnsFalse() {
        #expect(!SoapPropertiesChartView.showsFullNames(plotWidth: 300, fullNameWidth: 92, count: 6, gap: 8))
    }

    @Test func displayNames_AreUnique() {
        let names = Set(SoapQuality.allCases.map(\.displayName))
        #expect(names.count == SoapQuality.allCases.count)
    }

    @Test func displayName_Conditioning_IsSpelledInFull() {
        #expect(SoapQuality.conditioning.displayName == "Conditioning")
    }
}
