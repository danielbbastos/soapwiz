import Foundation

/// Matches extracted ingredient names against the inventory.
///
/// Matching is exact on `String.lookupKey` and nothing else. That key already
/// folds case, diacritics and internal whitespace, so "OLIVE OIL", "Óleo de
/// Oliva " and "Olive  Oil" all land on the same ingredient — but "Olive Pomace
/// Oil" does not, and deliberately so. A fuzzy match would silently attach the
/// wrong saponification value to a recipe, which is the same hazard as
/// inventing one: the lye weight comes out wrong and nothing downstream says so.
///
/// Anything that doesn't match exactly is surfaced to the user instead.
enum RecipeIngredientReconciler {
    static func reconcile(_ draft: RecipeImportDraft, against inventory: [Ingredient]) -> [RecipeImportRow] {
        let index = index(of: inventory)
        let slugIndex = slugIndex(of: inventory)
        return sections(of: draft).flatMap { imported, role in
            imported.map { row(for: $0, role: role, index: index, slugIndex: slugIndex) }
        }
    }

    /// Re-resolves the rows that are still unmatched, for use after the user
    /// creates an ingredient. Matched and skipped rows keep their decision —
    /// re-running the whole match would undo a skip the user just made.
    static func resolveUnmatched(in rows: [RecipeImportRow], against inventory: [Ingredient]) -> [RecipeImportRow] {
        let index = index(of: inventory)
        let slugIndex = slugIndex(of: inventory)
        return rows.map { row in
            guard case .unmatched = row.resolution else { return row }
            guard let ingredient = matched(row.imported.name, index: index, slugIndex: slugIndex) else { return row }
            var resolved = row
            resolved.resolution = .matched(ingredient)
            return resolved
        }
    }

    private static func row(
        for imported: ImportedIngredient,
        role: RecipeIngredientRole,
        index: [String: Ingredient],
        slugIndex: [String: Ingredient]
    ) -> RecipeImportRow {
        let match = matched(imported.name, index: index, slugIndex: slugIndex)
        return RecipeImportRow(
            imported: imported,
            role: role,
            resolution: match.map { .matched($0) } ?? .unmatched
        )
    }

    /// An inventory row for `name`: an exact name match, or failing that the row
    /// holding the catalog entry that ships under this name or one of its aliases.
    ///
    /// The alias step is still exact, not fuzzy. "Sweet Almond Oil" reaches the
    /// almond-oil row because the catalog lists that alias, never because the two
    /// strings look alike — the distinction this type exists to keep.
    private static func matched(
        _ name: String,
        index: [String: Ingredient],
        slugIndex: [String: Ingredient]
    ) -> Ingredient? {
        if let exact = index[name.lookupKey] { return exact }
        guard let entry = IngredientLibrary.entry(matching: name) else { return nil }
        return slugIndex[entry.slug]
    }

    /// Inventory keyed by library slug, with the same tie-break as `index(of:)`.
    private static func slugIndex(of inventory: [Ingredient]) -> [String: Ingredient] {
        var index: [String: Ingredient] = [:]
        for ingredient in inventory {
            let slug = ingredient.librarySlug
            guard !slug.isEmpty else { continue }
            guard let existing = index[slug] else {
                index[slug] = ingredient
                continue
            }
            if existing.sapValue == nil, ingredient.sapValue != nil {
                index[slug] = ingredient
            }
        }
        return index
    }

    /// Ingredients keyed by lookup key.
    ///
    /// Two ingredients can share a name while CloudKit is still collapsing a
    /// duplicate, so the tie is broken on usefulness rather than on arrival
    /// order: the copy that carries a saponification value is the one a recipe
    /// can actually be costed and calculated from.
    private static func index(of inventory: [Ingredient]) -> [String: Ingredient] {
        var index: [String: Ingredient] = [:]
        for ingredient in inventory {
            let key = ingredient.name.lookupKey
            guard !key.isEmpty else { continue }
            guard let existing = index[key] else {
                index[key] = ingredient
                continue
            }
            if existing.sapValue == nil, ingredient.sapValue != nil {
                index[key] = ingredient
            }
        }
        return index
    }

    private static func sections(of draft: RecipeImportDraft) -> [([ImportedIngredient], RecipeIngredientRole)] {
        [(draft.oils, .oil), (draft.additives, .additive), (draft.fragrances, .fragrance)]
    }
}
