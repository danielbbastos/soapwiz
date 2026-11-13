import SwiftData
import SwiftUI

/// Shows `content` while the pushed model is still stored, and pops itself the
/// moment it is not. A screen pushed on a stack can outlive its model (deleted
/// in another tab, or merged away by sync), and drawing a deleted model traps,
/// so the content is dropped before it can be read.
struct PushedModelGate<Content: View>: View {
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

struct StoredIngredientDestination: View {
    @Environment(InventoryRows.self) private var rows

    let ingredient: Ingredient
    private let id: PersistentIdentifier

    init(ingredient: Ingredient) {
        self.ingredient = ingredient
        id = ingredient.persistentModelID
    }

    var body: some View {
        PushedModelGate(isStored: rows.ingredients.contains { $0.persistentModelID == id }) {
            IngredientDetailView(ingredient: ingredient)
        }
    }
}

struct StoredPurchaseDestination: View {
    @Environment(InventoryRows.self) private var rows

    let purchase: IngredientPurchase
    private let id: PersistentIdentifier

    init(purchase: IngredientPurchase) {
        self.purchase = purchase
        id = purchase.persistentModelID
    }

    var body: some View {
        PushedModelGate(isStored: rows.purchases.contains { $0.persistentModelID == id }) {
            PurchaseDetailView(purchase: purchase)
        }
    }
}

struct StoredBatchDestination: View {
    @Environment(BatchRows.self) private var rows

    let batch: Batch
    private let id: PersistentIdentifier

    init(batch: Batch) {
        self.batch = batch
        id = batch.persistentModelID
    }

    var body: some View {
        PushedModelGate(isStored: rows.batches.contains { $0.persistentModelID == id }) {
            BatchDetailView(batch: batch)
        }
    }
}

struct StoredRecipeDestination: View {
    @Environment(RecipeRows.self) private var rows

    let recipe: Recipe
    private let id: PersistentIdentifier

    init(recipe: Recipe) {
        self.recipe = recipe
        id = recipe.persistentModelID
    }

    var body: some View {
        PushedModelGate(isStored: rows.recipes.contains { $0.persistentModelID == id }) {
            RecipeDetailView(recipe: recipe)
        }
    }
}
