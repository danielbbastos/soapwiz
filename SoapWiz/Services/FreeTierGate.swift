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

    func allows(_ feature: ProFeature) -> Bool {
        isUnlimited || FreeTierLimits.isAvailable(feature, isPro: false)
    }

    /// Unfiling is always allowed; filing is part of Pro, so a free user can
    /// still empty out collections they made before.
    func mayToggleCollection(isFiled: Bool) -> Bool {
        isFiled || allows(.collections)
    }

    func canCreateRecipe(in context: ModelContext) -> Bool {
        guard !isUnlimited else { return true }
        let count = (try? FreeTierLimits.recipeCount(in: context)) ?? 0
        return FreeTierLimits.canCreateRecipe(existingCount: count, isPro: false)
    }

    func importFit(for plan: RecipeTransferPlan, in context: ModelContext) -> FreeTierImportFit {
        FreeTierLimits.importFit(
            existingRecipes: (try? FreeTierLimits.recipeCount(in: context)) ?? 0,
            incomingRecipes: plan.recipeCount,
            isPro: isUnlimited
        )
    }
}
