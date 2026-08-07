import Foundation

/// Recipe text ready to send to the model, and what it cost to get there.
///
/// The budget the sanitizer enforces is in characters, not tokens, because the
/// iOS 26.0 SDK exposes no token counter — `SystemLanguageModel.contextSize`
/// and `tokenCount(for:)` arrived in 26.4. `RecipeTextSanitizer`'s character
/// budget is therefore a deliberate approximation at roughly four characters
/// per token, and the model itself remains the authority: an input it rejects
/// comes back as `exceededContextWindowSize`, which the import retries smaller.
struct SanitizedRecipeText: Equatable {
    let text: String
    let originalLength: Int
    let wasTrimmed: Bool

    var isEmpty: Bool { text.isEmpty }
}
