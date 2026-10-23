import Foundation
import Testing
@testable import SoapWiz

@Suite
struct CSVNumberParserTests {
    private let us = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    @Test func numbers_PreservesCountAndOrder() {
        let result = CSVNumberParser.numbers(in: ["3", "", "x", "1.5"], locale: us)
        #expect(result == [3, nil, nil, 1.5])
    }

    @Test func numbers_EmptyInput_ReturnsEmpty() {
        #expect(CSVNumberParser.numbers(in: [], locale: us).isEmpty)
    }

    @Test(arguments: ["", "   ", "abc", "-", "1,2,3x"])
    func numbers_EmptyOrUnreadable_ReturnsNil(cell: String) {
        #expect(CSVNumberParser.numbers(in: [cell], locale: us) == [nil])
    }

    @Test(arguments: ["-5", "-1,5", "€-5", "-€5", "−2"])
    func numbers_Negative_ReturnsNil(cell: String) {
        #expect(CSVNumberParser.numbers(in: [cell], locale: us) == [nil])
    }

    @Test func numbers_Zero_IsReadable() {
        #expect(CSVNumberParser.numbers(in: ["0", "0,0"], locale: us) == [0, 0])
    }

    @Test func numbers_CommaOnlyColumnInUSLocale_ReadsCommaAsDecimal() {
        #expect(CSVNumberParser.numbers(in: ["1,5", "12,50", "3"], locale: us) == [1.5, 12.5, 3])
    }

    @Test func numbers_PointOnlyColumnInGermanLocale_ReadsPointAsDecimal() {
        #expect(CSVNumberParser.numbers(in: ["1.5", "12.50", "3"], locale: german) == [1.5, 12.5, 3])
    }

    @Test func numbers_EuropeanGroupedColumn_ReadsGroupsAndDecimal() {
        #expect(CSVNumberParser.numbers(in: ["1.234,5", "2.000"], locale: us) == [1234.5, 2000])
    }

    @Test func numbers_USGroupedColumn_ReadsGroupsAndDecimal() {
        #expect(CSVNumberParser.numbers(in: ["1,234.5", "2,000"], locale: german) == [1234.5, 2000])
    }

    @Test func numbers_AmbiguousThousandsInUSLocale_IsGrouping() {
        #expect(CSVNumberParser.numbers(in: ["1,000"], locale: us) == [1000])
    }

    @Test func numbers_AmbiguousThousandsInGermanLocale_IsDecimal() {
        #expect(CSVNumberParser.numbers(in: ["1,000"], locale: german) == [1])
    }

    @Test func numbers_AmbiguousThousandsInColumnWithCommaDecimal_IsDecimal() {
        #expect(CSVNumberParser.numbers(in: ["1,000", "2,5"], locale: us) == [1, 2.5])
    }

    @Test func numbers_AmbiguousThousandsInColumnWithPointDecimal_IsGrouping() {
        #expect(CSVNumberParser.numbers(in: ["1,000", "2.5"], locale: german) == [1000, 2.5])
    }

    @Test func numbers_PointThousandsInColumnWithCommaDecimal_IsGrouping() {
        #expect(CSVNumberParser.numbers(in: ["1.000", "2,5"], locale: us) == [1000, 2.5])
    }

    @Test func numbers_LeadingZeroBeforeThreeDigits_IsDecimal() {
        #expect(CSVNumberParser.numbers(in: ["0,134", "2"], locale: us) == [0.134, 2])
        #expect(CSVNumberParser.numbers(in: ["0.134", "2"], locale: german) == [0.134, 2])
    }

    @Test func numbers_ConflictingMarks_UsesLocaleAndStaysLenient() {
        #expect(CSVNumberParser.numbers(in: ["1,5", "1.5"], locale: us) == [1.5, 1.5])
        #expect(CSVNumberParser.numbers(in: ["1,5", "1.5"], locale: german) == [1.5, 1.5])
    }

    @Test func numbers_SpaceGroupedValue_VotesWithoutTheSpace() {
        let portuguese = Locale(identifier: "pt_PT")
        #expect(CSVNumberParser.numbers(in: ["1 234,5"], locale: portuguese) == [1234.5])
    }

    @Test func numbers_CurrencySymbolBeforeOrAfter_IsIgnored() {
        #expect(CSVNumberParser.numbers(in: ["€ 5,50", "5,50€", "£1,25", " ¥ 7,5 "], locale: us) == [5.5, 5.5, 1.25, 7.5])
        #expect(CSVNumberParser.numbers(in: ["$12.50", "12.50 $"], locale: german) == [12.5, 12.5])
    }

    @Test func numbers_CurrencyCodeBeforeOrAfter_IsIgnoredCaseInsensitively() {
        #expect(CSVNumberParser.numbers(in: ["EUR 5,50", "5,50 eur", "12,5USD", "GBP3,25"], locale: us) == [5.5, 5.5, 12.5, 3.25])
    }

    @Test func numbers_BrazilianRealPrefix_IsIgnored() {
        #expect(CSVNumberParser.numbers(in: ["R$ 3,20", "R$12,00"], locale: us) == [3.2, 12])
    }

    @Test func numbers_CurrencyCodeLikeButUnknown_ReturnsNil() {
        #expect(CSVNumberParser.numbers(in: ["ABC 5"], locale: us) == [nil])
    }

    @Test func numbers_CurrencyOnly_ReturnsNil() {
        #expect(CSVNumberParser.numbers(in: ["€", "EUR"], locale: us) == [nil, nil])
    }
}
