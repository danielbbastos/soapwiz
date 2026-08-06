import Testing
import Foundation
@testable import SoapWiz

/// The override exists to make the UI reachable where the model can't run. It
/// must stay off unless deliberately switched on, or a debug build on an
/// eligible device would quietly stop testing the real extraction.
@Suite("Recipe import debug override")
struct RecipeImportDebugOverrideTests {

    /// The override being off is the whole guarantee: with it off, `current`
    /// answers from the system and a debug build behaves like any other.
    ///
    /// Deliberately no assertion on what `RecipeImportAvailability.current`
    /// then returns. Whether Apple Intelligence is present is a fact about the
    /// machine, not about this code — it is absent on a local simulator and
    /// present on the CI runner, so asserting either way tests the environment
    /// and fails somewhere.
    @Test func isEnabled_WithoutTheLaunchArgument_IsOff() {
        #expect(!ProcessInfo.processInfo.arguments.contains(RecipeImportDebugOverride.launchArgument))
        #expect(!RecipeImportDebugOverride.isEnabled)
    }

    @Test func cannedExtractor_ProducesADraftThatReachesEveryReviewBranch() async throws {
        let text = SanitizedRecipeText(text: "anything", originalLength: 8, wasTrimmed: false)
        let draft = try await CannedRecipeExtractor().extract(from: text)

        #expect(draft.hasAnyIngredient)
        #expect(draft.oils.count == 4)
        #expect(!draft.additives.isEmpty)
        #expect(!draft.fragrances.isEmpty)
        #expect(draft.amountsArePercentages)
    }

    @Test func cannedExtractor_EmptyText_StillFails() async throws {
        let empty = SanitizedRecipeText(text: "", originalLength: 0, wasTrimmed: false)
        await #expect(throws: RecipeImportError.nothingRecognised) {
            try await CannedRecipeExtractor().extract(from: empty)
        }
    }
}
