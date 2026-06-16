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
struct RecipeSeed: Hashable {
    let id = UUID()
    let ingredients: [Ingredient]
}

/// Cross-tab navigation state: which tab is selected and the History tab's
/// stack path. Lets flows that end in another tab (creating a batch from a
/// recipe) land the user there directly.
@Observable
@MainActor
final class AppNavigation {
    var selectedTab: AppTab = .inventory
    var historyPath = NavigationPath()

    /// Set by the inventory selection flow to request a seeded recipe; the
    /// Recipes tab observes it, opens the form, then clears it.
    var pendingRecipeSeed: RecipeSeed?

    /// Switches to the History tab showing `batch`'s detail screen, with the
    /// history list as the only screen underneath it.
    func showBatch(_ batch: Batch) {
        historyPath = NavigationPath([batch])
        selectedTab = .history
    }

    /// Switches to the Recipes tab and asks it to open the new-recipe form
    /// pre-filled with `ingredients`.
    func createRecipe(with ingredients: [Ingredient]) {
        pendingRecipeSeed = RecipeSeed(ingredients: ingredients)
        selectedTab = .recipes
    }
}
