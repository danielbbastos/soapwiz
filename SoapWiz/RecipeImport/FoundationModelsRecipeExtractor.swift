import Foundation
import FoundationModels

/// Extracts a recipe draft using Apple's on-device model.
///
/// Everything stays on the device: no API key, no backend, no per-import cost,
/// and no recipe text leaving the phone.
@available(iOS 26, macOS 26, *)
struct FoundationModelsRecipeExtractor: RecipeDraftExtracting {
    func extract(from text: SanitizedRecipeText) async throws -> RecipeImportDraft {
        guard !text.isEmpty else { throw RecipeImportError.nothingRecognised }

        // A fresh session per attempt. The transcript counts against the same
        // 4,096-token window as the prompt, so reusing one across retries would
        // make each attempt smaller than the last for no reason.
        let session = LanguageModelSession(instructions: Self.instructions)

        do {
            let response = try await session.respond(to: text.text, generating: GeneratedRecipeDraft.self)
            let draft = response.content.asImportDraft()
            guard draft.hasAnyIngredient else { throw RecipeImportError.nothingRecognised }
            return draft
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.importError(for: error)
        }
    }

    private static func importError(for error: LanguageModelSession.GenerationError) -> RecipeImportError {
        switch error {
        case .exceededContextWindowSize:
            .inputTooLong
        case .guardrailViolation, .refusal:
            .failed("The model wouldn't read that text.")
        case .assetsUnavailable, .rateLimited, .concurrentRequests:
            .failed("The on-device model is busy. Try again in a moment.")
        case .unsupportedLanguageOrLocale:
            .failed("The on-device model doesn't support this language yet.")
        case .decodingFailure, .unsupportedGuide:
            .failed("Couldn't make sense of that recipe.")
        @unknown default:
            .failed(error.localizedDescription)
        }
    }

    /// The chemistry prohibition is stated even though the schema already makes
    /// it impossible to return a SAP value. Guided generation is the guarantee;
    /// this is here so the model doesn't try to be helpful by folding an
    /// invented saponification figure into an amount or a name.
    private static let instructions = """
        You read soap-making recipes out of messy text and report what they say.

        Report only what the text states. Copy ingredient names exactly as written; do not \
        translate them, expand them, or correct their spelling. Copy each amount exactly as \
        written and put its unit in the unit field.

        Never state a saponification value, a SAP value, a density, or a fatty-acid composition, \
        and never fold one into another field. Never calculate a lye or water weight. If the text \
        does not give a value, leave that field empty rather than estimating it.

        Ignore anything that is not the recipe: introductions, stories, safety notices, step-by-step \
        instructions, comments and navigation.
        """
}
