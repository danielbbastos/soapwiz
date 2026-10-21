import Foundation
import SwiftData

/// Whether an import fits the free tier, and which limits it passes.
struct FreeTierImportFit: Equatable {
    let existingRecipes: Int
    let existingCustomIngredients: Int
    let incomingRecipes: Int
    let incomingCustomIngredients: Int
    let exceedsRecipes: Bool
    let exceedsCustomIngredients: Bool

    var fits: Bool { !exceedsRecipes && !exceedsCustomIngredients }

    /// The limit the upgrade sheet should name: recipes first, as the file is
    /// made of them.
    var upgradeReason: ProUpgradeReason? {
        if exceedsRecipes { return .recipeImportLimit }
        if exceedsCustomIngredients { return .customIngredientImportLimit }
        return nil
    }

    /// One sentence per limit passed, for the review screen.
    var explanations: [String] {
        var lines: [String] = []
        if exceedsRecipes {
            let noun = incomingRecipes == 1 ? "recipe" : "recipes"
            lines.append(
                "This file has \(incomingRecipes) \(noun); the free version keeps "
                + "\(FreeTierLimits.recipeCap) and you have \(existingRecipes)."
            )
        }
        if exceedsCustomIngredients {
            let noun = incomingCustomIngredients == 1 ? "custom ingredient" : "custom ingredients"
            lines.append(
                "This file brings \(incomingCustomIngredients) new \(noun); the free version keeps "
                + "\(FreeTierLimits.customIngredientCap) and you have \(existingCustomIngredients)."
            )
        }
        return lines
    }
}

enum ProFeature {
    case collections
    case reminders
}

/// What the free tier allows.
///
/// Creating is blocked while the count is at or over the cap. Items already
/// over it (a refund, a device that synced before a refund) are never
/// touched: this only answers "may another one be made". A backup restore is
/// the exception that is checked up front, since it would bring them all in.
enum FreeTierLimits {
    static let recipeCap = 3
    static let customIngredientCap = 3

    static func canCreateRecipe(existingCount: Int, isPro: Bool) -> Bool {
        isPro || existingCount < recipeCap
    }

    static func canCreateCustomIngredient(existingCount: Int, isPro: Bool) -> Bool {
        isPro || existingCount < customIngredientCap
    }

    static func isAvailable(_ feature: ProFeature, isPro: Bool) -> Bool {
        switch feature {
        case .collections, .reminders:
            return isPro
        }
    }

    /// Whether an ingredient is the user's own rather than the library's.
    ///
    /// A row with no slug is the user's own. A library row becomes the user's
    /// own once its name differs from the one the catalog ships (trimmed, case
    /// ignored); renaming it back stops it counting. Chemistry and category
    /// edits don't count: they adjust a library ingredient to the maker's
    /// supplier rather than add a new one. A slug the catalog doesn't know
    /// can't be compared, so it isn't counted.
    static func isCustomIngredient(librarySlug: String, name: String) -> Bool {
        if librarySlug.isEmpty { return true }
        guard let bundledName = IngredientLibrary.bundledName(for: librarySlug) else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBundledName = bundledName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.caseInsensitiveCompare(trimmedBundledName) != .orderedSame
    }

    /// Whether saving an edit would turn a library row into a custom one. Only
    /// that crossing takes a slot: a row that is custom already (or stays
    /// library) takes none, and renaming a custom row back to the catalog's
    /// name frees one rather than needing one.
    static func renameNeedsSlot(librarySlug: String, oldName: String, newName: String) -> Bool {
        !isCustomIngredient(librarySlug: librarySlug, name: oldName)
            && isCustomIngredient(librarySlug: librarySlug, name: newName)
    }

    /// Whether a whole import fits, all or nothing: half a shared file would
    /// leave recipes pointing at ingredients that were never made. A kind the
    /// file brings none of can't be exceeded by it, even when the store is
    /// already over that cap.
    static func importFit(
        existingRecipes: Int,
        existingCustomIngredients: Int,
        incomingRecipes: Int,
        incomingCustomIngredients: Int,
        isPro: Bool
    ) -> FreeTierImportFit {
        FreeTierImportFit(
            existingRecipes: existingRecipes,
            existingCustomIngredients: existingCustomIngredients,
            incomingRecipes: incomingRecipes,
            incomingCustomIngredients: incomingCustomIngredients,
            exceedsRecipes: !isPro && incomingRecipes > 0 && existingRecipes + incomingRecipes > recipeCap,
            exceedsCustomIngredients: !isPro && incomingCustomIngredients > 0
                && existingCustomIngredients + incomingCustomIngredients > customIngredientCap
        )
    }

    /// Whether a backup may replace the store. A restore replaces everything,
    /// so the backup's own counts are compared with the caps, not added to
    /// what the store holds.
    static func restoreFits(recipes: Int, customIngredients: Int, isPro: Bool) -> Bool {
        isPro || (recipes <= recipeCap && customIngredients <= customIngredientCap)
    }

    static func restoreFits(_ backup: BackupData, isPro: Bool) -> Bool {
        restoreFits(
            recipes: backup.recipes.count,
            customIngredients: customIngredientCount(in: backup),
            isPro: isPro
        )
    }

    /// The backup's custom ingredients, by the rule the app counts its own: an
    /// ingredient written before the library existed has no slug and is custom.
    static func customIngredientCount(in backup: BackupData) -> Int {
        backup.ingredients.count { isCustomIngredient(librarySlug: $0.librarySlug ?? "", name: $0.name) }
    }

    static func recipeCount(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<Recipe>())
    }

    /// Hidden ingredients count: hiding one doesn't free a slot.
    ///
    /// Rows with no slug are always custom, so they are counted by the store
    /// as everything that isn't a library row. Only the library rows are
    /// fetched, and only the two fields the rule reads: the full fetch faulted
    /// every ingredient (photos included) and cost 20 to 50 ms on an iPad.
    /// Subtracting rather than matching an empty slug keeps a row whose slug
    /// the store holds as null counted as the custom row it reads as.
    static func customIngredientCount(in context: ModelContext) throws -> Int {
        let total = try context.fetchCount(FetchDescriptor<Ingredient>())
        var libraryRows = FetchDescriptor<Ingredient>(predicate: #Predicate { !$0.librarySlug.isEmpty })
        libraryRows.propertiesToFetch = [\.librarySlug, \.name]
        let library = try context.fetch(libraryRows)
        let renamedCount = library.count { isCustomIngredient(librarySlug: $0.librarySlug, name: $0.name) }
        return total - library.count + renamedCount
    }
}
