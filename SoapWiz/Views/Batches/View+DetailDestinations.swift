import SwiftUI

extension View {
    /// Routes the batch and recipe screens a stack can be asked to push from a
    /// usage row or a batch's recipe link. A pushed model that is deleted
    /// meanwhile pops its screen; see `PushedModelGate`.
    func batchAndRecipeDestinations() -> some View {
        navigationDestination(for: Batch.self) { StoredBatchDestination(batch: $0) }
            .navigationDestination(for: Recipe.self) { StoredRecipeDestination(recipe: $0) }
    }

    /// Everything the Inventory list's stack can push: an ingredient, and from
    /// it a batch and that batch's recipe.
    func inventoryDestinations() -> some View {
        navigationDestination(for: Ingredient.self) { IngredientDetailView(ingredient: $0) }
            .batchAndRecipeDestinations()
    }

    /// Routes the ingredient, batch and recipe screens Home's cards push onto
    /// Home's own stack. A batch's recipe link and an ingredient's purchases
    /// push from inside those screens, so the stack answers for them too.
    func homeNavigationDestinations() -> some View {
        navigationDestination(for: Ingredient.self) { StoredIngredientDestination(ingredient: $0) }
            .batchAndRecipeDestinations()
    }
}
