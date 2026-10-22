import Foundation

/// One incoming ingredient and what will become of it.
@MainActor
struct RecipeTransferIngredientPlan: Identifiable {
    /// Position in the payload's ingredient pool.
    ///
    /// Identity by position rather than by name, because the pool is built by
    /// model identity on the sending side: two rows sharing a name — a CloudKit
    /// duplicate the sender hasn't merged yet — are two separate entries here,
    /// and keying on the name would collapse them in every `ForEach`.
    let id: Int

    let incoming: RecipeTransferIngredient

    /// The role its first line item uses it in, which decides the category a
    /// created ingredient is filed under.
    let role: RecipeIngredientRole

    /// The inventory ingredient it matched, or `nil` when it will be created.
    let existing: Ingredient?

    /// Whether `existing` was found by library slug rather than by name.
    ///
    /// Not on its own a reason to stay quiet about chemistry: the slug says both
    /// rows came from one catalog entry, not that either still holds its values.
    /// See `hasChemistryConflict`.
    let matchedBySlug: Bool

    /// The slug a newly created row should take: the incoming one, but only when
    /// this build's catalog actually ships that entry.
    ///
    /// An unknown slug — a sender on a newer catalog — is deliberately dropped. Were
    /// it adopted, the installer would count the entry as present once the update
    /// shipped and skip it, leaving the sender's unverified chemistry wearing the
    /// "from the built-in library" badge for good. Left blank, the row is instead
    /// adopted by name or alias on the next launch, keeping the user's recipes
    /// pointing at it while flagging any chemistry that differs as custom.
    var adoptableSlug: String? {
        guard let slug = incoming.librarySlug, !slug.isEmpty else { return nil }
        return IngredientLibrary.bundledName(for: slug) == nil ? nil : slug
    }

    var name: String { incoming.name }

    var willBeCreated: Bool { existing == nil }

    /// Whether creating it would use one of the free tier's custom slots.
    var countsAsCustomIngredient: Bool {
        FreeTierLimits.isCustomIngredient(librarySlug: adoptableSlug ?? "", name: incoming.name)
    }

    /// This entry matched to an ingredient the user picked. Not a slug match,
    /// so a pick whose chemistry differs from the sender's is reported.
    func matched(to ingredient: Ingredient) -> RecipeTransferIngredientPlan {
        RecipeTransferIngredientPlan(
            id: id,
            incoming: incoming,
            role: role,
            existing: ingredient,
            matchedBySlug: false
        )
    }

    /// The category a created ingredient is filed under, by name.
    var suggestedCategoryName: String {
        switch role {
        case .oil: IngredientCategory.Name.oils
        case .fragrance: IngredientCategory.Name.fragrances
        case .additive: IngredientCategory.Name.additives
        }
    }

    /// Whether the recipient already has this ingredient with different
    /// chemistry from the sender's.
    ///
    /// Compared only on the values that change a calculation. A different
    /// fatty-acid profile moves the soap-property stats but not the lye weight,
    /// and is included for the same reason: the recipe will not read the way it
    /// read on the sender's device, and the user should hear that from the app
    /// rather than notice it later.
    var hasChemistryConflict: Bool {
        guard let existing else { return false }
        // Silence needs both sides holding the catalog's own values. A slug match
        // against a row the user has customised is exactly when the warning is
        // wanted: their values are the ones the recipe will be calculated from,
        // and the sender never saw them.
        if matchedBySlug, existing.isPristineLibraryRow { return false }
        return existing.sapValue != incoming.sapValue
            || existing.kohSapValue != incoming.kohSapValue
            || existing.density != incoming.density
            || existing.fattyAcidProfile != incoming.fattyAcidProfile
    }
}
