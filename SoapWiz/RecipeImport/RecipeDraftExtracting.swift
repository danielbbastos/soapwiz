import Foundation

/// Turns sanitized recipe text into a draft.
///
/// A protocol rather than a concrete type so everything around it — the view
/// model, the review screen, the reconciliation — is testable without Apple
/// Intelligence, which is unavailable in the simulator and on ineligible
/// devices. It is also the seam a future cloud or multimodal extractor slots
/// into without touching the rest of the pipeline.
protocol RecipeDraftExtracting {
    func extract(from text: SanitizedRecipeText) async throws -> RecipeImportDraft
}

enum RecipeImportError: LocalizedError, Equatable {
    case modelUnavailable(String)
    case inputTooLong
    case nothingRecognised
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason): reason
        case .inputTooLong: "That's too long to read in one go."
        case .nothingRecognised: "No recipe found in that text."
        case .failed(let reason): reason
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .modelUnavailable: "Apple Intelligence needs to be on for recipe import."
        case .inputTooLong: "Paste just the ingredient list and the lye settings, without the surrounding article."
        case .nothingRecognised: "Check the text includes the oils and their amounts, then try again."
        case .failed: "Try again, or paste a tidier copy of the recipe."
        }
    }
}
