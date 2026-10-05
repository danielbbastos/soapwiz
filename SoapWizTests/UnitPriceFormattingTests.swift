import Testing
import Foundation
@testable import SoapWiz

@Suite
struct UnitPriceFormattingTests {

    private let locale = Locale(identifier: "en_US")

    @Test func unitPriceFormatted_FourDecimals_KeepsAllFour() {
        #expect(0.0125.unitPriceFormatted(currencyCode: "USD", locale: locale) == "$0.0125")
    }

    @Test func unitPriceFormatted_ThreeDecimals_DropsTrailingZero() {
        #expect(0.012.unitPriceFormatted(currencyCode: "USD", locale: locale) == "$0.012")
    }

    @Test func unitPriceFormatted_OneDecimal_PadsToTwo() {
        #expect(3.5.unitPriceFormatted(currencyCode: "USD", locale: locale) == "$3.50")
    }

    @Test func unitPriceFormatted_WholeNumber_PadsToTwo() {
        #expect(2.0.unitPriceFormatted(currencyCode: "USD", locale: locale) == "$2.00")
    }

    @Test func unitPriceFormatted_MoreThanFourDecimals_RoundsToFour() {
        #expect(0.012_345.unitPriceFormatted(currencyCode: "USD", locale: locale) == "$0.0123")
    }

    @Test func unitPriceFormatted_Zero_ShowsTwoDecimals() {
        #expect(0.0.unitPriceFormatted(currencyCode: "USD", locale: locale) == "$0.00")
    }

    @Test func unitPriceFormatted_OtherLocale_UsesItsSeparators() {
        let result = 0.0125.unitPriceFormatted(currencyCode: "EUR", locale: Locale(identifier: "pt_PT"))
        #expect(result.contains("0,0125"))
        #expect(result.contains("€"))
    }
}
