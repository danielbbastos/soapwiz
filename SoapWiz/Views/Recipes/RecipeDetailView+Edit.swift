import SwiftUI
import SwiftData

/// Opening the recipe form to edit this recipe.
extension RecipeDetailView {

    /// A push on iPhone, as before SW-89; on iPad the form covers the screen.
    /// See `RecipeFormRequest.opensFullScreen`.
    @ToolbarContentBuilder
    var editToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if RecipeFormRequest.opensFullScreen {
                Button("Edit") {
                    isAwaitingEditClose = true
                    navigation.recipeFormRequest = .edit(recipe)
                }
            } else {
                NavigationLink(value: RecipeEditRoute(recipe: recipe)) {
                    Text("Edit")
                }
            }
        }
    }

    /// Reloads once this screen's own full-screen edit has fully closed. Skipped
    /// for a recipe deleted meanwhile, which a screen left in another tab can
    /// still hold: reading one traps.
    func reloadAfterOwnEdit() {
        guard isAwaitingEditClose, !navigation.isRecipeFormOnScreen else { return }
        isAwaitingEditClose = false
        guard recipe.modelContext != nil, !recipe.isDeleted else { return }
        reload()
    }
}
