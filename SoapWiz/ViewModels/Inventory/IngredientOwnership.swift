import Foundation

/// What puts an ingredient among the user's own: the one rule behind the
/// Inventory list's My Ingredients scope and Home's first-run check.
enum IngredientOwnership {
    /// The user made it, bought it (a used-up purchase still counts), changed
    /// its chemistry, or starred it. Ignores `tracksInventory`.
    static func isOwned(_ ingredient: Ingredient, stock: StockLevels) -> Bool {
        !ingredient.isLibraryInstalled ||
            stock.hasPurchases(ingredient) ||
            ingredient.hasCustomChemistry ||
            ingredient.isFavorite
    }
}
