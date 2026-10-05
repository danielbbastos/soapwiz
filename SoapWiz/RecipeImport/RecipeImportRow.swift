import Foundation
import SwiftData

/// What became of one extracted ingredient name.
enum RecipeImportResolution: Equatable {
    /// The name matched an ingredient already in the inventory, so its
    /// saponification value, density and fatty-acid profile come with it.
    case matched(Ingredient)
    /// No inventory ingredient has this name. The user creates it or skips it;
    /// nothing is guessed on their behalf.
    case unmatched
    /// The user chose to leave this ingredient out.
    case skipped
}

/// One row on the review screen: an extracted ingredient, which recipe section
/// it belongs to, and how it resolved against the inventory.
struct RecipeImportRow: Identifiable {
    let id: UUID
    let imported: ImportedIngredient
    let role: RecipeIngredientRole
    var resolution: RecipeImportResolution {
        didSet { matchedSlug = ingredient?.librarySlug ?? "" }
    }

    /// The matched ingredient's merge key, taken while it is certainly still in
    /// the store, so `resolvedAfterMerge(in:)` can find the survivor if the
    /// duplicate merge deletes it while the review screen is up. See
    /// `LiveIngredient`.
    private(set) var matchedSlug: String

    init(imported: ImportedIngredient, role: RecipeIngredientRole, resolution: RecipeImportResolution) {
        self.id = imported.id
        self.imported = imported
        self.role = role
        self.resolution = resolution
        if case .matched(let ingredient) = resolution {
            self.matchedSlug = ingredient.librarySlug
        } else {
            self.matchedSlug = ""
        }
    }

    /// This row with its match moved onto the ingredient the merge kept. A match
    /// with nothing left to move onto goes back to unmatched, for the user to
    /// create or skip again, rather than staying on a row the screen would read.
    func resolvedAfterMerge(in context: ModelContext) -> RecipeImportRow {
        guard case .matched(let captured) = resolution else { return self }
        var row = self
        row.resolution = LiveIngredient.resolve(captured, slug: matchedSlug, in: context).map { .matched($0) } ?? .unmatched
        return row
    }

    var ingredient: Ingredient? {
        if case .matched(let ingredient) = resolution { return ingredient }
        return nil
    }

    var isResolved: Bool {
        switch resolution {
        case .matched, .skipped: true
        case .unmatched: false
        }
    }

    /// The category a newly created ingredient should default to, so the create
    /// form opens on the right kind of thing — and, for oils, with the SAP field
    /// already showing.
    var suggestedCategoryName: String {
        switch role {
        case .oil: IngredientCategory.Name.oils
        case .fragrance: IngredientCategory.Name.fragrances
        case .additive: IngredientCategory.Name.additives
        }
    }
}
