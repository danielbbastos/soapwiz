import Foundation

/// When the recipe form's Stats column follows edits to the oil rows.
enum RecipeStatsRefresh {
    /// The pause after the last keystroke before Stats follows. Long enough
    /// that a hesitation between erasing a percentage and typing the next one
    /// doesn't redraw.
    static let delay: Duration = .milliseconds(750)

    /// Whether Stats should show `live` at once rather than after `delay`:
    /// nothing is shown yet, or rows were added, removed or replaced. An edit
    /// to an amount or lock state keeps the same rows and waits.
    static func updatesImmediately(from shown: [OilIngredientDraft]?, to live: [OilIngredientDraft]) -> Bool {
        guard let shown else { return true }
        return shown.map(\.id) != live.map(\.id)
    }
}
