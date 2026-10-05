import Foundation
import SwiftData

/// The ingredients ticked in `IngredientPickerView` but not yet added.
///
/// Kept by id, each with the slug taken when it was ticked, while the row is
/// certainly still in the store. The duplicate merge can delete a ticked row
/// while the picker is up — a joining device's first sync does — and an id
/// alone would then match nothing: the kept copy shows unticked, yet Done stays
/// enabled and adds nothing. See `LiveIngredient`.
struct PendingIngredientSelection {
    private var slugs: [PersistentIdentifier: String] = [:]

    var isEmpty: Bool { slugs.isEmpty }

    func contains(_ id: PersistentIdentifier) -> Bool {
        slugs[id] != nil
    }

    mutating func insert(_ ingredient: Ingredient) {
        slugs[ingredient.persistentModelID] = ingredient.librarySlug
    }

    mutating func toggle(_ ingredient: Ingredient) {
        if contains(ingredient.persistentModelID) {
            slugs[ingredient.persistentModelID] = nil
        } else {
            insert(ingredient)
        }
    }

    /// Moves every tick on a row the merge deleted onto the row it kept. A tick
    /// with nothing left to move onto is dropped, so Done disables rather than
    /// adding nothing.
    mutating func followMerge(in context: ModelContext) {
        var followed: [PersistentIdentifier: String] = [:]
        for (id, slug) in slugs {
            if let row = LiveIngredient.storedRow(id: id, slug: slug, in: context) {
                followed[row.persistentModelID] = row.librarySlug
            }
        }
        slugs = followed
    }
}
