import SwiftUI

enum AppTab: Hashable {
    case inventory
    case recipes
    case history
    case settings
}

/// A request to open the new-recipe form pre-seeded with a set of ingredients.
/// The `id` makes each request distinct so the Recipes tab reacts even when the
/// same ingredients are sent twice.
struct RecipeSeed: Hashable, Identifiable {
    let id = UUID()
    let ingredients: [Ingredient]
}

/// Cross-tab navigation state: which tab is selected plus pending hand-offs.
/// Lets flows that end in another tab (creating a batch from a recipe) land
/// the user there directly.
@Observable
@MainActor
final class AppNavigation {
    var selectedTab: AppTab = .inventory

    /// Set by the inventory selection flow to request a seeded recipe; the
    /// Recipes tab observes it, opens the form, then clears it.
    var pendingRecipeSeed: RecipeSeed?

    /// Set by the batch-creation flow; the History tab picks it up, selects it
    /// in the split view, then clears it.
    var pendingBatch: Batch?

    /// Switches to the History tab and asks it to show `batch`'s detail.
    func showBatch(_ batch: Batch) {
        pendingBatch = batch
        selectedTab = .history
    }

    /// Switches to the Recipes tab and asks it to open the new-recipe form
    /// pre-filled with `ingredients`.
    func createRecipe(with ingredients: [Ingredient]) {
        pendingRecipeSeed = RecipeSeed(ingredients: ingredients)
        selectedTab = .recipes
    }
}
