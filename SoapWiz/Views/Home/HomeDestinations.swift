import SwiftData
import SwiftUI

extension View {
    /// Routes the ingredient, batch and recipe screens Home's cards push onto
    /// Home's own stack. A batch's recipe link and an ingredient's purchases
    /// push from inside those screens, so the stack answers for them too.
    func homeNavigationDestinations() -> some View {
        navigationDestination(for: Ingredient.self) { HomeIngredientDestination(ingredient: $0) }
            .navigationDestination(for: Batch.self) { HomeBatchDestination(batch: $0) }
            .navigationDestination(for: Recipe.self) { HomeRecipeDestination(recipe: $0) }
    }
}

/// Shows `content` while the pushed model is still stored, and pops itself the
/// moment it is not. A screen pushed on Home can outlive its model (deleted in
/// another tab, or merged away by sync), and drawing a deleted model traps, so
/// the content is dropped before it can be read.
private struct HomeStoredGate<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    let isStored: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isStored {
            content()
        } else {
            Color.clear
                .ledgerBackground()
                .onAppear { dismiss() }
        }
    }
}

private struct HomeIngredientDestination: View {
    @Environment(InventoryRows.self) private var rows

    let ingredient: Ingredient
    private let id: PersistentIdentifier

    init(ingredient: Ingredient) {
        self.ingredient = ingredient
        id = ingredient.persistentModelID
    }

    var body: some View {
        HomeStoredGate(isStored: rows.ingredients.contains { $0.persistentModelID == id }) {
            IngredientDetailView(ingredient: ingredient)
        }
    }
}

private struct HomeBatchDestination: View {
    @Environment(BatchRows.self) private var rows

    let batch: Batch
    private let id: PersistentIdentifier

    init(batch: Batch) {
        self.batch = batch
        id = batch.persistentModelID
    }

    var body: some View {
        HomeStoredGate(isStored: rows.batches.contains { $0.persistentModelID == id }) {
            BatchDetailView(batch: batch)
        }
    }
}

private struct HomeRecipeDestination: View {
    @Environment(RecipeRows.self) private var rows

    let recipe: Recipe
    private let id: PersistentIdentifier

    init(recipe: Recipe) {
        self.recipe = recipe
        id = recipe.persistentModelID
    }

    var body: some View {
        HomeStoredGate(isStored: rows.recipes.contains { $0.persistentModelID == id }) {
            RecipeDetailView(recipe: recipe)
        }
    }
}
