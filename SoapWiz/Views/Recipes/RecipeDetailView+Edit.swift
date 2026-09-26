import SwiftUI

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
}
