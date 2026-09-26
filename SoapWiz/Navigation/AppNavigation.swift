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

/// A push of the recipe form in edit mode. Distinct from pushing the `Recipe`
/// itself, which every stack already routes to `RecipeDetailView`.
struct RecipeEditRoute: Hashable {
    let recipe: Recipe
}

/// A `.soapwizrecipe` file another app handed to SoapWiz to open. The `id`
/// keeps two opens of the same file distinct, so the Recipes tab reacts to the
/// second the way it did to the first.
struct RecipeFileImport: Hashable {
    let id = UUID()
    let url: URL
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

    /// Set when another app opens a recipe file in SoapWiz; the Recipes tab
    /// observes it, opens the import review for the file, then clears it.
    var pendingRecipeFileImport: RecipeFileImport?

    /// The recipe form open full screen, on iPad. Held here rather than by the
    /// screen that opened it so no tab switch or layout change can close it, and
    /// so a file opened meanwhile can wait for it (SW-89).
    var recipeFormRequest: RecipeFormRequest? {
        didSet {
            if recipeFormRequest != nil { isRecipeFormOnScreen = true }
        }
    }

    /// True from the moment the full-screen form is requested until it has
    /// finished closing. `recipeFormRequest` turns nil as the cover starts to
    /// leave, and nothing else can be presented until it has gone.
    private(set) var isRecipeFormOnScreen = false

    /// Counts the full-screen recipe form's finished dismissals, for screens
    /// that act once it has gone.
    private(set) var recipeFormClosings = 0

    /// Called by the cover's `onDismiss`, once it is fully off screen.
    func recipeFormDidClose() {
        isRecipeFormOnScreen = false
        recipeFormClosings += 1
    }

    /// Drops the form without waiting for its dismissal, for a restore: the
    /// interface is torn down around it, so its `onDismiss` can't be relied on
    /// to clear `isRecipeFormOnScreen`, and a flag left set would hold every
    /// later file import back.
    func discardRecipeForm() {
        recipeFormRequest = nil
        isRecipeFormOnScreen = false
    }

    /// Hands out the recipe file waiting to open, once: nil while the recipe
    /// form is on screen, closing included, since the import review can't go up
    /// over it, and nil again after the file has been taken.
    func takePendingRecipeFileImport() -> RecipeFileImport? {
        guard !isRecipeFormOnScreen, let request = pendingRecipeFileImport else { return nil }
        pendingRecipeFileImport = nil
        return request
    }

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

    /// Switches to the Recipes tab and asks it to open `url`, a `.soapwizrecipe`
    /// file another app handed in.
    func openRecipeFile(_ url: URL) {
        pendingRecipeFileImport = RecipeFileImport(url: url)
        selectedTab = .recipes
    }
}
