import Testing
import Foundation
import SwiftUI
@testable import SoapWiz

/// Numbers the user types, read in their own locale (SW-179). The case that
/// started it: "1,500" in an English region was stored as 1.5.
@Suite("LocaleDecimal")
struct LocaleDecimalTests {

    struct Case: CustomTestStringConvertible, Sendable {
        let text: String
        let locale: String
        let expected: Double?
        var testDescription: String { "\"\(text)\" in \(locale)" }
    }

    @Test(arguments: [
        Case(text: "1,500", locale: "en_US", expected: 1500),
        Case(text: "1,5", locale: "en_US", expected: 1.5),
        Case(text: "1.5", locale: "en_US", expected: 1.5),
        Case(text: "1,234,567.89", locale: "en_US", expected: 1_234_567.89),
        Case(text: "1,500", locale: "pt_PT", expected: 1.5),
        Case(text: "1.5", locale: "pt_PT", expected: 1.5),
        Case(text: "1.500", locale: "pt_PT", expected: 1.5),
        Case(text: "0,0625", locale: "pt_PT", expected: 0.0625),
        Case(text: "1\u{00A0}234,5", locale: "pt_PT", expected: 1234.5),
        Case(text: "1.500", locale: "de_DE", expected: 1500),
        Case(text: "1.5", locale: "de_DE", expected: 1.5),
        Case(text: "1.234,5", locale: "de_DE", expected: 1234.5),
        Case(text: "1,500", locale: "de_DE", expected: 1.5),
        Case(text: "1 234,5", locale: "fr_FR", expected: 1234.5),
        Case(text: "1\u{202F}234,5", locale: "fr_FR", expected: 1234.5),
        Case(text: "1.500", locale: "fr_FR", expected: 1.5),
        Case(text: "1’234.5", locale: "de_CH", expected: 1234.5),
        Case(text: "1,23,456", locale: "en_IN", expected: 123_456),
        Case(text: "0.134", locale: "de_DE", expected: 0.134),
        Case(text: "0.915", locale: "es_ES", expected: 0.915),
        Case(text: "0.134", locale: "en_DE", expected: 0.134),
        Case(text: "0,125", locale: "en_US", expected: 0.125),
        Case(text: "0,500", locale: "en_US", expected: 0.5),
        Case(text: "012,345", locale: "en_US", expected: 12.345)
    ])
    func parse_ReadsTheLocaleSeparators(_ testCase: Case) {
        #expect(LocaleDecimal.parse(testCase.text, locale: Locale(identifier: testCase.locale)) == testCase.expected)
    }

    /// Both separators present: the last one is the decimal, whatever the
    /// locale, because that reading is the only one that fits.
    @Test func parse_BothSeparators_LastOneIsTheDecimal() {
        let english = Locale(identifier: "en_US")
        #expect(LocaleDecimal.parse("1.234,5", locale: english) == 1234.5)
        #expect(LocaleDecimal.parse("1,234.5", locale: Locale(identifier: "pt_PT")) == 1234.5)
    }

    @Test func parse_LeadingMinus_IsNegative() {
        #expect(LocaleDecimal.parse("-50", locale: Locale(identifier: "en_US")) == -50)
        #expect(LocaleDecimal.parse("\u{2212}1,5", locale: Locale(identifier: "pt_PT")) == -1.5)
    }

    @Test func parse_PartialInputWhileTyping_ReadsWhatIsThere() {
        let portuguese = Locale(identifier: "pt_PT")
        #expect(LocaleDecimal.parse("1,", locale: portuguese) == 1)
        #expect(LocaleDecimal.parse(",5", locale: portuguese) == 0.5)
        #expect(LocaleDecimal.parse(",", locale: portuguese) == 0)
    }

    @Test(arguments: ["", "   ", "abc", "1.2.3", "1,2,3", "1,5.000,2", "12a", "1.23,45,6", "-", "--5", "5-"])
    func parse_Unreadable_ReturnsNil(_ text: String) {
        #expect(LocaleDecimal.parse(text, locale: Locale(identifier: "en_US")) == nil)
    }

    @Test func isReadable_EmptyOrNumber_IsTrue() {
        let english = Locale(identifier: "en_US")
        #expect(LocaleDecimal.isReadable("", locale: english))
        #expect(LocaleDecimal.isReadable("  ", locale: english))
        #expect(LocaleDecimal.isReadable("1,500", locale: english))
        #expect(!LocaleDecimal.isReadable("1.2.3", locale: english))
        #expect(!LocaleDecimal.isReadable("0,13,5", locale: english))
    }

    /// What the forms pre-fill must read back as the same number.
    @Test(arguments: ["en_US", "pt_PT", "de_DE", "fr_FR", "de_CH", "en_IN"])
    func parse_FormattedValue_RoundTrips(_ identifier: String) {
        let locale = Locale(identifier: identifier)
        for value in [0.0, 0.25, 12.5, 1234.56, 1_234_567.0] {
            let grouped = value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
            let ungrouped = value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(locale))
            #expect(LocaleDecimal.parse(grouped, locale: locale) == value, "\(grouped)")
            #expect(LocaleDecimal.parse(ungrouped, locale: locale) == value, "\(ungrouped)")
        }
    }

    /// The text field filter used to rewrite every comma as a point, which is
    /// what turned "1,500" into 1.5. It now leaves separators as typed.
    @Test @MainActor func decimalOnly_KeepsSeparatorsAndDropsLetters() {
        var stored = ""
        let binding = Binding(get: { stored }, set: { stored = $0 }).decimalOnly(locale: Locale(identifier: "en_US"))

        binding.wrappedValue = "1,500"
        #expect(stored == "1,500")
        binding.wrappedValue = "12.5 g"
        #expect(stored == "12.5")
    }

    @Test @MainActor func decimalOnly_KeepsTheLocaleGroupingSpace() {
        var stored = ""
        let binding = Binding(get: { stored }, set: { stored = $0 }).decimalOnly(locale: Locale(identifier: "fr_FR"))

        binding.wrappedValue = "1\u{202F}234,5"

        #expect(stored == "1\u{202F}234,5")
        #expect(LocaleDecimal.parse(stored, locale: Locale(identifier: "fr_FR")) == 1234.5)
    }
}
