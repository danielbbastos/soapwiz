import Foundation

/// Checks a model-extracted draft against the text the model read.
///
/// Greedy generation makes the model consistent, not correct. On device it has
/// invented amounts for a shopping list with none, taken the superfat from the
/// lye weight, and listed sodium hydroxide as an oil. Each of those reaches the
/// lye calculation, so each is corrected here deterministically, whatever the
/// model returned.
///
/// The direction is always towards less: a row is dropped, an amount becomes 0,
/// a setting is cleared. The review screen then shows a gap for the user to
/// fill rather than a number nobody wrote.
enum RecipeImportDraftChecker {
    /// The draft after every `Step` has run in order, except those in `skipping`.
    static func checked(
        _ draft: RecipeImportDraft,
        against text: String,
        skipping: Set<Step> = []
    ) -> RecipeImportDraft {
        let context = Context(draft: draft, text: text)
        return Step.allCases
            .filter { !skipping.contains($0) }
            .reduce(draft) { $1.apply(to: $0, context: context) }
    }
}
