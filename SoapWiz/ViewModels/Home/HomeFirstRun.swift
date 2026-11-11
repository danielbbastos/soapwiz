import Foundation

/// Whether Home has nothing of the user's to show yet, which swaps its cards
/// for the first-run screen. Purely data-driven: the screen goes the moment
/// anything exists.
enum HomeFirstRun {
    static func isEmpty(
        recipes: [Recipe],
        batches: [Batch],
        shoppingItems: [ShoppingListItem],
        ingredients: [Ingredient],
        purchases: [IngredientPurchase]
    ) -> Bool {
        guard recipes.isEmpty, batches.isEmpty, shoppingItems.isEmpty else { return false }
        let stock = StockLevels(purchases)
        return !ingredients.contains { IngredientOwnership.isOwned($0, stock: stock) }
    }
}
