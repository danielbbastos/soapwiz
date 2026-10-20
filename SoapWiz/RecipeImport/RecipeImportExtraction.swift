import Foundation

/// The model read of a pasted recipe: sanitize, extract, and retry once with a
/// smaller budget when the model says the text doesn't fit. Shared by the
/// import view model and the evaluation runner so both exercise the same path.
enum RecipeImportExtraction {
    /// `onSanitized` is called with each text handed to the model, `onRetry`
    /// just before the second attempt, and `onPartial` with streaming drafts.
    static func run(
        rawText: String,
        knownIngredientNames: [String],
        using extractor: RecipeDraftExtracting,
        onSanitized: (SanitizedRecipeText) -> Void = { _ in },
        onRetry: () -> Void = {},
        onPartial: (RecipeImportDraft) -> Void = { _ in }
    ) async throws -> RecipeImportDraft {
        var text = RecipeTextSanitizer.sanitize(
            rawText,
            knownIngredientNames: knownIngredientNames,
            characterBudget: RecipeTextSanitizer.defaultCharacterBudget
        )
        onSanitized(text)

        guard !text.isEmpty else { throw RecipeImportError.nothingRecognised }

        do {
            return try await extractor.extract(from: text, onPartial: onPartial)
        } catch RecipeImportError.inputTooLong {
            // The character budget is an estimate — the model is the authority
            // on what fits. When it says no, halve the budget and try the
            // densest half rather than handing the failure straight to the user.
            text = RecipeTextSanitizer.sanitize(
                rawText,
                knownIngredientNames: knownIngredientNames,
                characterBudget: RecipeTextSanitizer.defaultCharacterBudget / 2
            )
            onSanitized(text)
            onRetry()
            return try await extractor.extract(from: text, onPartial: onPartial)
        }
    }
}
