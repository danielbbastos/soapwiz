import Testing
import Foundation
@testable import SoapWiz

@Suite("String lookup key")
struct StringLookupKeyTests {

    @Test func lookupKey_DiffersOnlyByCase_Matches() {
        #expect("Oils".lookupKey == "oils".lookupKey)
        #expect("OILS".lookupKey == "oils".lookupKey)
    }

    @Test func lookupKey_DiffersOnlyByDiacritics_Matches() {
        #expect("Óleos".lookupKey == "Oleos".lookupKey)
        #expect("Manteiga de Cacau".lookupKey == "Mantéiga de Cacáu".lookupKey)
    }

    @Test func lookupKey_SurroundingWhitespace_IsTrimmed() {
        #expect("  Oils  ".lookupKey == "Oils".lookupKey)
        #expect("\tOils\n".lookupKey == "Oils".lookupKey)
    }

    @Test func lookupKey_InternalWhitespaceRuns_CollapseToOneSpace() {
        #expect("Olive  Oil".lookupKey == "Olive Oil".lookupKey)
        #expect("Olive \t Oil".lookupKey == "Olive Oil".lookupKey)
    }

    @Test func lookupKey_DistinctNames_DoNotMatch() {
        #expect("Oils".lookupKey != "Waxes".lookupKey)
        #expect("Olive Oil".lookupKey != "OliveOil".lookupKey)
    }

    @Test func lookupKey_EmptyAndWhitespaceOnly_ShareTheSameKey() {
        #expect("".lookupKey == "   ".lookupKey)
        #expect("".lookupKey.isEmpty)
    }

    /// The folding must not depend on `Locale.current`, or two devices in
    /// different regions would group synced rows differently.
    @Test func lookupKey_IsIndependentOfCurrentLocale() {
        #expect("Istanbul".lookupKey == "ISTANBUL".lookupKey)
        #expect("ıstanbul".lookupKey != "Istanbul".lookupKey)
    }
}
