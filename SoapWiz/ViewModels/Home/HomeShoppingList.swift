import Foundation
import SwiftData

/// What Home's Shopping list card says: how many lines are still to buy and how
/// many more the stock suggests.
enum HomeShoppingList {
    struct Summary: Equatable {
        let toBuyCount: Int
        let suggestedCount: Int
    }

    /// `nil` when inventory tracking is off or there is nothing to say.
    static func make(
        items: [ShoppingListItem],
        ingredients: [Ingredient],
        purchases: [IngredientPurchase],
        tracksInventory: Bool,
        now: Date
    ) -> Summary? {
        guard tracksInventory else { return nil }

        let boughtDates = ShoppingListBought.dates(items: items, purchases: purchases)
        let toBuyCount = ShoppingListBought.split(items: items, boughtDates: boughtDates).toBuy.count
        let suggestedCount = ShoppingSuggestions.make(
            ingredients: ingredients,
            purchases: purchases,
            listedIngredientIDs: Set(items.compactMap { $0.ingredient?.persistentModelID }),
            tracksInventory: true,
            now: now
        ).count

        guard toBuyCount > 0 || suggestedCount > 0 else { return nil }
        return Summary(toBuyCount: toBuyCount, suggestedCount: suggestedCount)
    }
}
