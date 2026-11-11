import Foundation
import SwiftData

/// Which shopping list lines have been bought since they were added, worked out
/// from the purchases rather than stored.
enum ShoppingListBought {
    /// For each linked item with a purchase of its ingredient recorded after the
    /// item was added, the earliest such purchase's date. A purchase counts when
    /// it was saved after the item (`createdAt`), whatever date the user gave it,
    /// since purchases are often logged in bulk with back-dated entries. One
    /// without a `createdAt` (made before it existed) counts when its date is at
    /// or after the item's creation instant. Unlinked items never appear.
    static func dates(
        items: [ShoppingListItem],
        purchases: [IngredientPurchase]
    ) -> [PersistentIdentifier: Date] {
        var purchasesByIngredient: [PersistentIdentifier: [IngredientPurchase]] = [:]
        for purchase in purchases {
            guard let id = purchase.ingredient?.persistentModelID else { continue }
            purchasesByIngredient[id, default: []].append(purchase)
        }
        var result: [PersistentIdentifier: Date] = [:]
        for item in items {
            guard let ingredientID = item.ingredient?.persistentModelID,
                  let earliest = purchasesByIngredient[ingredientID]?
                    .filter({ isBought(after: item.createdAt, purchase: $0) })
                    .map(\.dateOfPurchase)
                    .min() else { continue }
            result[item.persistentModelID] = earliest
        }
        return result
    }

    /// The lines still to buy (not ticked, not bought since they were added) and
    /// the rest, each in the order given.
    static func split(
        items: [ShoppingListItem],
        boughtDates: [PersistentIdentifier: Date]
    ) -> (toBuy: [ShoppingListItem], checked: [ShoppingListItem]) {
        var toBuy: [ShoppingListItem] = []
        var checked: [ShoppingListItem] = []
        for item in items {
            if !item.isChecked && boughtDates[item.persistentModelID] == nil {
                toBuy.append(item)
            } else {
                checked.append(item)
            }
        }
        return (toBuy, checked)
    }

    private static func isBought(after itemCreatedAt: Date, purchase: IngredientPurchase) -> Bool {
        if let savedAt = purchase.createdAt { return savedAt > itemCreatedAt }
        return purchase.dateOfPurchase >= itemCreatedAt
    }
}
