import Testing
import Foundation
@testable import SoapWiz

@Suite("Home title margin")
struct HomeTitleMarginTests {

    @Test func cardsOnIPadLandscapeSitJustInsideThePadding() {
        #expect(HomeLayout.titleMargin(width: 1_180, isFirstRun: false) == 30)
    }

    @Test func cardsOnA13InchLandscapeAreCentred() {
        #expect(HomeLayout.titleMargin(width: 1_366, isFirstRun: false) == 123)
    }

    @Test func cardsAtTheWideThresholdKeepOnlyThePadding() {
        #expect(HomeLayout.titleMargin(width: 1_000, isFirstRun: false) == 16)
    }

    @Test func firstRunColumnIsCentredInsideThePadding() {
        #expect(HomeLayout.titleMargin(width: 1_180, isFirstRun: true) == 310)
        #expect(HomeLayout.titleMargin(width: 1_000, isFirstRun: true) == 220)
    }

    @Test func narrowWidthsUseTheReadableMargin() {
        #expect(HomeLayout.titleMargin(width: 999, isFirstRun: false) == 149.5)
        #expect(HomeLayout.titleMargin(width: 820, isFirstRun: false) == 60)
        #expect(HomeLayout.titleMargin(width: 820, isFirstRun: true) == 60)
    }

    @Test func phoneWidthsUseTheSystemMargin() {
        #expect(HomeLayout.titleMargin(width: 390, isFirstRun: false) == nil)
    }
}
