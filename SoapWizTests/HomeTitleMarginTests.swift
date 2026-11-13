import SwiftUI
import Testing
import Foundation
@testable import SoapWiz

@Suite("Home title margin")
struct HomeTitleMarginTests {

    @Test func cardsOnIPadLandscapeSitJustInsideThePadding() {
        #expect(HomeLayout.titleMargin(width: 1_180, isFirstRun: false, dynamicTypeSize: .large) == 30)
    }

    @Test func cardsOnA13InchLandscapeAreCentred() {
        #expect(HomeLayout.titleMargin(width: 1_366, isFirstRun: false, dynamicTypeSize: .large) == 123)
    }

    @Test func cardsAtTheWideThresholdKeepOnlyThePadding() {
        #expect(HomeLayout.titleMargin(width: 1_000, isFirstRun: false, dynamicTypeSize: .large) == 16)
    }

    @Test func firstRunColumnIsCentredInsideThePadding() {
        #expect(HomeLayout.titleMargin(width: 1_180, isFirstRun: true, dynamicTypeSize: .large) == 310)
        #expect(HomeLayout.titleMargin(width: 1_000, isFirstRun: true, dynamicTypeSize: .large) == 220)
    }

    @Test func narrowWidthsUseTheReadableMargin() {
        #expect(HomeLayout.titleMargin(width: 999, isFirstRun: false, dynamicTypeSize: .large) == 149.5)
        #expect(HomeLayout.titleMargin(width: 820, isFirstRun: false, dynamicTypeSize: .large) == 60)
        #expect(HomeLayout.titleMargin(width: 820, isFirstRun: true, dynamicTypeSize: .large) == 60)
    }

    @Test func phoneWidthsUseTheSystemMargin() {
        #expect(HomeLayout.titleMargin(width: 390, isFirstRun: false, dynamicTypeSize: .large) == nil)
    }
}
