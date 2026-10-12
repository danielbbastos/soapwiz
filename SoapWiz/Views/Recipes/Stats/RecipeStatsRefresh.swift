import Foundation
import SwiftData

/// When the recipe form's Stats column follows edits to the oil rows.
enum RecipeStatsRefresh {
    /// The pause after the last keystroke before Stats follows. Long enough
    /// that a hesitation between erasing a percentage and typing the next one
    /// doesn't redraw.
    static let delay: Duration = .milliseconds(750)

    /// Whether Stats should show `live` at once rather than after `delay`:
    /// nothing is shown yet, or rows were added, removed or replaced, or a row
    /// now points at a different ingredient. The last happens after a duplicate
    /// merge: the row keeps its identity but moves onto the surviving
    /// ingredient, and the one still shown may be deleted, so Stats must not
    /// keep reading it for the delay. An edit to an amount or lock state keeps
    /// the same rows and ingredients, and waits.
    static func updatesImmediately(from shown: [OilIngredientDraft]?, to live: [OilIngredientDraft]) -> Bool {
        guard let shown else { return true }
        return shown.map(RowKey.init) != live.map(RowKey.init)
    }

    private struct RowKey: Equatable {
        let id: UUID
        let ingredientID: PersistentIdentifier

        init(_ draft: OilIngredientDraft) {
            id = draft.id
            ingredientID = draft.ingredient.persistentModelID
        }
    }
}
