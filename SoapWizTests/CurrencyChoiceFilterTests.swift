import Testing
import Foundation
@testable import SoapWiz

@Suite("CurrencyChoice – filter")
struct CurrencyChoiceFilterTests {

    private let choices = [
        CurrencyChoice(code: "BRL", label: "Real brasileiro (BRL)"),
        CurrencyChoice(code: "EUR", label: "Euro (EUR)"),
        CurrencyChoice(code: "SEK", label: "Svensk krona (SEK)"),
        CurrencyChoice(code: "XOF", label: "Franc CFA (XOF)")
    ]

    @Test func filter_EmptyQuery_ReturnsAll() {
        #expect(CurrencyChoice.filter(choices, matching: "") == choices)
    }

    @Test func filter_WhitespaceQuery_ReturnsAll() {
        #expect(CurrencyChoice.filter(choices, matching: "  \n ") == choices)
    }

    @Test func filter_CodeQuery_MatchesCaseInsensitively() {
        #expect(CurrencyChoice.filter(choices, matching: "eur").map(\.code) == ["EUR"])
    }

    @Test func filter_NameSubstring_Matches() {
        #expect(CurrencyChoice.filter(choices, matching: "kron").map(\.code) == ["SEK"])
    }

    @Test func filter_DiacriticsIgnored_Matches() {
        #expect(CurrencyChoice.filter(choices, matching: "FRÁNC").map(\.code) == ["XOF"])
    }

    @Test func filter_SurroundingWhitespace_IsTrimmed() {
        #expect(CurrencyChoice.filter(choices, matching: " euro ").map(\.code) == ["EUR"])
    }

    @Test func filter_NoMatch_ReturnsEmpty() {
        #expect(CurrencyChoice.filter(choices, matching: "zzz").isEmpty)
    }
}
