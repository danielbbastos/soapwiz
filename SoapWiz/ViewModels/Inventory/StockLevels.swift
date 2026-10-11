import Foundation
import SwiftData

/// Each ingredient's stock, summed from one fetch of every purchase.
///
/// Reading `ingredient.purchases` per ingredient is what this replaces: after a
/// CloudKit import the purchases are faults, and walking them fired a
/// relationship fault per ingredient and an object fault per purchase.
struct StockLevels {
    private let remaining: [PersistentIdentifier: Double]

    init(_ purchases: [IngredientPurchase]) {
        var remaining: [PersistentIdentifier: Double] = [:]
        for purchase in purchases {
            guard let id = purchase.ingredient?.persistentModelID else { continue }
            remaining[id, default: 0] += purchase.remainingAmount
        }
        self.remaining = remaining
    }

    func hasPurchases(_ ingredient: Ingredient) -> Bool {
        remaining[ingredient.persistentModelID] != nil
    }

    func totalRemaining(_ ingredient: Ingredient) -> Double {
        remaining[ingredient.persistentModelID] ?? 0
    }

    func isLowStock(_ ingredient: Ingredient) -> Bool {
        guard let threshold = ingredient.lowStockThreshold else { return false }
        return totalRemaining(ingredient) <= threshold
    }
}
