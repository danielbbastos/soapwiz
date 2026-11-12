import SwiftUI

extension View {
    /// Routes the batch and recipe screens a stack can be asked to push from a
    /// usage row or a batch's recipe link.
    func batchAndRecipeDestinations() -> some View {
        navigationDestination(for: Batch.self) { BatchDetailView(batch: $0) }
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
    }

    /// Everything the Inventory list's stack can push: an ingredient, and from
    /// it a batch and that batch's recipe.
    func inventoryDestinations() -> some View {
        navigationDestination(for: Ingredient.self) { IngredientDetailView(ingredient: $0) }
            .batchAndRecipeDestinations()
    }
}
