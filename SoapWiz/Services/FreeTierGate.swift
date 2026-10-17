import Foundation
import SwiftData

/// The free tier's limits as one screen sees them: unlimited for Pro and for
/// the onboarding tour's sandbox, counted against the store otherwise.
///
/// A count that can't be read lets the action through. Blocking on a failed
/// fetch would lock a paying or well-within-limits user out of making anything.
struct FreeTierGate: Equatable {
    let isUnlimited: Bool

    init(isPro: Bool, isTourSandbox: Bool = false) {
        isUnlimited = isPro || isTourSandbox
    }

    func canCreateRecipe(in context: ModelContext) -> Bool {
        guard !isUnlimited else { return true }
        let count = (try? FreeTierLimits.recipeCount(in: context)) ?? 0
        return FreeTierLimits.canCreateRecipe(existingCount: count, isPro: false)
    }

    func canCreateCustomIngredient(in context: ModelContext) -> Bool {
        guard !isUnlimited else { return true }
        let count = (try? FreeTierLimits.customIngredientCount(in: context)) ?? 0
        return FreeTierLimits.canCreateCustomIngredient(existingCount: count, isPro: false)
    }

    /// Whether an edit may be saved under its new name: always, unless the
    /// rename turns a library row into a custom one with no slot left.
    func allowsRename(librarySlug: String, oldName: String, newName: String, in context: ModelContext) -> Bool {
        guard FreeTierLimits.renameNeedsSlot(librarySlug: librarySlug, oldName: oldName, newName: newName) else {
            return true
        }
        return canCreateCustomIngredient(in: context)
    }

    func importFit(for plan: RecipeTransferPlan, in context: ModelContext) -> FreeTierImportFit {
        FreeTierLimits.importFit(
            existingRecipes: (try? FreeTierLimits.recipeCount(in: context)) ?? 0,
            existingCustomIngredients: (try? FreeTierLimits.customIngredientCount(in: context)) ?? 0,
            incomingRecipes: plan.recipeCount,
            incomingCustomIngredients: plan.customIngredientsToCreate.count,
            isPro: isUnlimited
        )
    }
}
