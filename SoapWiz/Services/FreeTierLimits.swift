import Foundation
import SwiftData

enum ProFeature {
    case collections
    case reminders
}

/// What the free tier allows.
///
/// Creating is blocked while the count is at or over the cap. Items already
/// over it (a backup restore, a refund, a device that synced before a refund)
/// are never touched: this only answers "may another one be made".
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

    static func recipeCount(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<Recipe>())
    }

    /// Hidden ingredients count: hiding one doesn't free a slot.
    static func customIngredientCount(in context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<Ingredient>())
            .count { isCustomIngredient(librarySlug: $0.librarySlug, name: $0.name) }
    }
}
