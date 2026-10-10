import Testing
import SwiftUI
@testable import SoapWiz

@Suite("Collection colour swatches")
@MainActor
struct CollectionColorSwatchTests {

    @Test func swatch_PigmentedColours_MatchTheirPigment() throws {
        for color in CollectionColor.allCases where color != .neutral {
            let pigment = try #require(color.pigment)
            #expect(color.swatch == pigment)
        }
    }

    @Test func swatch_Neutral_FallsBackToAppAccent() {
        #expect(CollectionColor.neutral.pigment == nil)
        #expect(CollectionColor.neutral.swatch == Color("AccentColor"))
    }

    @Test func swatch_AllColours_AreDistinct() {
        let swatches = Set(CollectionColor.allCases.map(\.swatch))

        #expect(swatches.count == CollectionColor.allCases.count)
    }
}
