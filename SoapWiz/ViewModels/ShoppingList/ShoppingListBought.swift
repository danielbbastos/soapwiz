import Foundation
import SwiftData

/// Which shopping list lines have been bought since they were added, worked out
/// from the purchases rather than stored.
enum ShoppingListBought {
    /// For each linked item with a purchase of its ingredient dated on or after
    /// the day the item was added, the earliest such purchase date. Days are
    /// compared, not instants, so a purchase logged for that day counts even if
    /// it is stored at midnight. Unlinked items never appear.
    static func dates(
        items: [ShoppingListItem],
        purchases: [IngredientPurchase],
        calendar: Calendar = .current
    ) -> [PersistentIdentifier: Date] {
        var purchaseDates: [PersistentIdentifier: [Date]] = [:]
        for purchase in purchases {
            guard let id = purchase.ingredient?.persistentModelID else { continue }
            purchaseDates[id, default: []].append(purchase.dateOfPurchase)
        }
        var result: [PersistentIdentifier: Date] = [:]
        for item in items {
            let addedDay = calendar.startOfDay(for: item.createdAt)
            guard let ingredientID = item.ingredient?.persistentModelID,
                  let earliest = purchaseDates[ingredientID]?.filter({ $0 >= addedDay }).min() else { continue }
            result[item.persistentModelID] = earliest
        }
        return result
    }
}
