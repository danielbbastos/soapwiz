import Foundation
import SwiftData

/// Each ingredient's stock, summed from one fetch of every purchase.
///
/// Reading `ingredient.purchases` per ingredient is what this replaces: after a
/// CloudKit import the purchases are faults, and walking them fired a
/// relationship fault per ingredient and an object fault per purchase.
///
/// It also hands each inventory row its `IngredientStock`, so a deleted or
/// synced purchase redraws the row (SW-317).
struct StockLevels {
    private let levels: [PersistentIdentifier: IngredientStock]

    init(_ purchases: [IngredientPurchase]) {
        var remaining: [PersistentIdentifier: Double] = [:]
        var expiries: [PersistentIdentifier: [Date]] = [:]
        for purchase in purchases {
            guard let id = purchase.ingredient?.persistentModelID else { continue }
            remaining[id, default: 0] += purchase.remainingAmount
            if let expiry = purchase.expiryDate {
                expiries[id, default: []].append(expiry)
            }
        }
        levels = remaining.reduce(into: [:]) { result, entry in
            result[entry.key] = IngredientStock(
                remaining: entry.value,
                hasPurchases: true,
                expiries: (expiries[entry.key] ?? []).sorted()
            )
        }
    }

    func stock(for ingredient: Ingredient) -> IngredientStock {
        levels[ingredient.persistentModelID] ?? .none
    }

    func hasPurchases(_ ingredient: Ingredient) -> Bool {
        stock(for: ingredient).hasPurchases
    }

    func totalRemaining(_ ingredient: Ingredient) -> Double {
        stock(for: ingredient).remaining
    }

    func isLowStock(_ ingredient: Ingredient) -> Bool {
        guard let threshold = ingredient.lowStockThreshold else { return false }
        return totalRemaining(ingredient) <= threshold
    }
}
