import Foundation
import SwiftData

/// Whether an import fits the free tier's recipe limit.
struct FreeTierImportFit: Equatable {
    let existingRecipes: Int
    let incomingRecipes: Int
    let exceedsRecipes: Bool

    var fits: Bool { !exceedsRecipes }

    /// The sentence for the review screen, or `nil` when the import fits.
    var explanation: String? {
        guard exceedsRecipes else { return nil }
        let noun = incomingRecipes == 1 ? "recipe" : "recipes"
        return "You’re adding \(incomingRecipes) \(noun); the free version keeps "
            + "\(FreeTierLimits.recipeCap) and you have \(existingRecipes)."
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

    static func canCreateRecipe(existingCount: Int, isPro: Bool) -> Bool {
        isPro || existingCount < recipeCap
    }

    static func isAvailable(_ feature: ProFeature, isPro: Bool) -> Bool {
        switch feature {
        case .collections, .reminders:
            return isPro
        }
    }

    /// Whether an import fits, all or nothing: half of what the user chose
    /// would leave recipes pointing at ingredients that were never made. The
    /// count is that of the recipes ticked, not of the file. A file with no
    /// recipes can't exceed the cap, even when the store is already over it.
    static func importFit(
        existingRecipes: Int,
        incomingRecipes: Int,
        isPro: Bool
    ) -> FreeTierImportFit {
        FreeTierImportFit(
            existingRecipes: existingRecipes,
            incomingRecipes: incomingRecipes,
            exceedsRecipes: !isPro && incomingRecipes > 0 && existingRecipes + incomingRecipes > recipeCap
        )
    }

    /// Whether a backup may replace the store. A restore replaces everything,
    /// so the backup's own count is compared with the cap, not added to what
    /// the store holds.
    static func restoreFits(recipes: Int, isPro: Bool) -> Bool {
        isPro || recipes <= recipeCap
    }

    static func restoreFits(_ backup: BackupData, isPro: Bool) -> Bool {
        restoreFits(recipes: backup.recipes.count, isPro: isPro)
    }

    static func recipeCount(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<Recipe>())
    }
}
