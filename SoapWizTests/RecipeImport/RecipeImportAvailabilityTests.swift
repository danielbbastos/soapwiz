import Testing
import Foundation
@testable import SoapWiz

@Suite("RecipeImportAvailability")
struct RecipeImportAvailabilityTests {

    private static let allCases: [RecipeImportAvailability] = [
        .available, .appleIntelligenceOff, .deviceNotEligible, .modelNotReady, .unsupportedOS
    ]

    @Test func isAvailable_OnlyForAvailable() {
        #expect(RecipeImportAvailability.available.isAvailable)
        for state in Self.allCases where state != .available {
            #expect(!state.isAvailable)
        }
    }

    /// Every state has to say something. An empty footer is the silence this
    /// section exists to remove.
    @Test func settingsFooter_IsNeverEmpty() {
        for state in Self.allCases {
            #expect(!state.settingsFooter.isEmpty, "\(state) has no footer")
        }
    }

    @Test func statusText_IsShortAndNeverEmpty() {
        for state in Self.allCases {
            #expect(!state.statusText.isEmpty, "\(state) has no status")
            #expect(state.statusText.count <= 24, "\(state) status is too long for the row")
        }
    }

    @Test func statusSymbol_IsNeverEmpty() {
        for state in Self.allCases {
            #expect(!state.statusSymbol.isEmpty, "\(state) has no symbol")
        }
    }

    /// Only the states the user can do something about should read as prompts.
    /// Telling someone to act on hardware they can't change is worse than
    /// saying nothing.
    @Test func isActionable_OnlyWhereTheUserCanAct() {
        #expect(RecipeImportAvailability.appleIntelligenceOff.isActionable)
        #expect(RecipeImportAvailability.modelNotReady.isActionable)
        #expect(!RecipeImportAvailability.available.isActionable)
        #expect(!RecipeImportAvailability.deviceNotEligible.isActionable)
        #expect(!RecipeImportAvailability.unsupportedOS.isActionable)
    }

    @Test func explanation_IsEmptyOnlyWhenAvailable() {
        #expect(RecipeImportAvailability.available.explanation.isEmpty)
        for state in Self.allCases where state != .available {
            #expect(!state.explanation.isEmpty, "\(state) has no explanation")
        }
    }

    /// The available footer has to mention the gesture — the entry point is a
    /// long press on the Recipes FAB and nothing else on screen reveals it.
    @Test func settingsFooter_WhenAvailable_ExplainsHowToStart() {
        let footer = RecipeImportAvailability.available.settingsFooter
        #expect(footer.lowercased().contains("hold"))
        #expect(footer.contains("Recipes"))
    }
}
