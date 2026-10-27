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
    /// `sectionsAreStated` is for a draft `RecipeTextExportReader` read from a
    /// SoapWiz copy, which names each row's section itself. The name guess that
    /// refiles an unmatched row exists for model drafts, where the model sorts
    /// rows by position; on a copy it can only be wrong, moving an additive
    /// such as "Scent fixative" to the fragrances. It is a parameter rather
    /// than a field on the draft so that a model's draft cannot claim it.
    static func reconcile(
        _ draft: RecipeImportDraft,
        against inventory: [Ingredient],
        sectionsAreStated: Bool = false
    ) -> [RecipeImportRow] {
        let index = IngredientIndex(inventory)
        return sections(of: draft).flatMap { imported, role in
            imported.compactMap {
                row(for: $0, role: role, sectionsAreStated: sectionsAreStated, index: index)
            }
        }
    }

    /// Re-resolves the rows that are still unmatched, for use after the user
    /// creates an ingredient. Matched and skipped rows keep their decision —
    /// re-running the whole match would undo a skip the user just made.
    static func resolveUnmatched(in rows: [RecipeImportRow], against inventory: [Ingredient]) -> [RecipeImportRow] {
        let index = IngredientIndex(inventory)
        return rows.map { row in
            guard case .unmatched = row.resolution else { return row }
            guard let ingredient = matched(row.imported.name, listedAsOil: false, index: index) else {
                return row
            }
            var resolved = row
            resolved.resolution = resolution(for: ingredient)
            return resolved
        }
    }

    /// How a row resolves once it has an ingredient.
    ///
    /// A lye is skipped rather than matched. The recipe calculates its lye, and
    /// one counted among the oils or additives would throw that weight off, so
    /// it stays out of the recipe while its name still reaches the notes. This
    /// covers the ingredient the user creates from the review screen, which
    /// can land in the Lyes category, as well as one found by matching.
    static func resolution(for ingredient: Ingredient) -> RecipeImportResolution {
        ingredient.category?.name == IngredientCategory.Name.lyes ? .skipped : .matched(ingredient)
    }

    /// A matched row takes the section its ingredient's category belongs to,
    /// not the one the model chose: Honey is an additive however it was listed.
    /// An unmatched row takes the section its name makes evident, when it does.
    /// A match in the Lyes category yields no row at all, because a recipe
    /// calculates its lye rather than listing it.
    private static func row(
        for imported: ImportedIngredient,
        role: RecipeIngredientRole,
        sectionsAreStated: Bool,
        index: IngredientIndex
    ) -> RecipeImportRow? {
        guard let match = matched(imported.name, listedAsOil: role == .oil, index: index) else {
            return RecipeImportRow(
                imported: imported,
                role: sectionsAreStated ? role : ImportedIngredientName.evidentRole(of: imported.name) ?? role,
                resolution: .unmatched
            )
        }
        guard match.category?.name != IngredientCategory.Name.lyes else { return nil }
        return RecipeImportRow(
            imported: imported,
            role: match.category?.ingredientRole ?? role,
            resolution: .matched(match)
        )
    }

    /// An inventory row for `name`: for each of its lookup spellings in turn, an
    /// exact name match, or failing that the row holding the catalog entry that
    /// ships under that spelling or one of its aliases.
    ///
    /// Every step is still exact, not fuzzy. "Sweet Almond Oil" reaches the
    /// almond-oil row because the catalog lists that alias, and "Tea Tree EO"
    /// reaches Tea Tree Essential Oil because EO is spelled out — never because
    /// two strings look alike, the distinction this type exists to keep.
    private static func matched(
        _ name: String,
        listedAsOil: Bool,
        index: IngredientIndex
    ) -> Ingredient? {
        for candidate in ImportedIngredientName.lookupCandidates(for: name, listedAsOil: listedAsOil) {
            if let exact = index.ingredient(named: candidate) { return exact }
            if let entry = IngredientLibrary.entry(matching: candidate), let installed = index.ingredient(slug: entry.slug) {
                return installed
            }
        }
        return nil
    }

    private static func sections(of draft: RecipeImportDraft) -> [([ImportedIngredient], RecipeIngredientRole)] {
        [(draft.oils, .oil), (draft.additives, .additive), (draft.fragrances, .fragrance)]
    }
}
