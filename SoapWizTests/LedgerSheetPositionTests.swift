import Testing
@testable import SoapWiz

@Suite
struct LedgerSheetPositionTests {

    @Test func position_SingleRow_IsOnly() {
        #expect(LedgerSheetPosition.position(index: 0, count: 1) == .only)
    }

    @Test func position_TwoRows_AreFirstAndLast() {
        #expect(LedgerSheetPosition.position(index: 0, count: 2) == .first)
        #expect(LedgerSheetPosition.position(index: 1, count: 2) == .last)
    }

    @Test func position_ThreeOrMoreRows_AreFirstMiddleLast() {
        #expect(LedgerSheetPosition.position(index: 0, count: 3) == .first)
        #expect(LedgerSheetPosition.position(index: 1, count: 3) == .middle)
        #expect(LedgerSheetPosition.position(index: 2, count: 3) == .last)
        #expect(LedgerSheetPosition.position(index: 4, count: 10) == .middle)
        #expect(LedgerSheetPosition.position(index: 9, count: 10) == .last)
    }

    @Test func position_ZeroOrNegativeCount_IsOnly() {
        #expect(LedgerSheetPosition.position(index: 0, count: 0) == .only)
        #expect(LedgerSheetPosition.position(index: 3, count: -2) == .only)
    }

    @Test func position_IndexPastEnd_ClampsToLast() {
        #expect(LedgerSheetPosition.position(index: 5, count: 3) == .last)
    }

    @Test func position_NegativeIndex_ClampsToFirst() {
        #expect(LedgerSheetPosition.position(index: -1, count: 3) == .first)
    }

    @Test func rounding_MatchesPosition() {
        #expect(LedgerSheetPosition.only.roundsTop && LedgerSheetPosition.only.roundsBottom)
        #expect(LedgerSheetPosition.first.roundsTop && !LedgerSheetPosition.first.roundsBottom)
        #expect(!LedgerSheetPosition.middle.roundsTop && !LedgerSheetPosition.middle.roundsBottom)
        #expect(!LedgerSheetPosition.last.roundsTop && LedgerSheetPosition.last.roundsBottom)
    }
}
