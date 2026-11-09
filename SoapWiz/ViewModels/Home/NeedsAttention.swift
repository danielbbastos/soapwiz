import Foundation
import SwiftData

/// What the Home tab's Needs attention card shows: the stock that is out,
/// expired, low or about to expire, and what the expiring stock is worth.
///
/// Ranks with the shopping list's own rules, but ignores its dismissals and
/// listed ingredients: Home is about the shelf, not about what is on order.
struct NeedsAttention {
    struct Row: Identifiable {
        let ingredient: Ingredient
        let reason: ShoppingSuggestionReason
        let stamp: IngredientStockStamp
        let remaining: Double
        let unit: String
        let supplierName: String?
        let lowStockThreshold: Double?
        let earliestExpired: Date?
        let valueAtRisk: Double

        var id: PersistentIdentifier { ingredient.persistentModelID }
    }

    let rows: [Row]
    let moreCount: Int
    let valueAtRisk: Double

    static func make(
        ingredients: [Ingredient],
        purchases: [IngredientPurchase],
        tracksInventory: Bool,
        now: Date = .now,
        calendar: Calendar = .current,
        rowLimit: Int = 4
    ) -> NeedsAttention? {
        guard tracksInventory else { return nil }

        var purchasesByIngredient: [PersistentIdentifier: [IngredientPurchase]] = [:]
        for purchase in purchases {
            guard let id = purchase.ingredient?.persistentModelID else { continue }
            purchasesByIngredient[id, default: []].append(purchase)
        }

        let cutoff = calendar.date(byAdding: .month, value: 1, to: now)

        var qualifying: [Row] = []
        var totalAtRisk = 0.0
        for ingredient in ingredients {
            guard !ingredient.isHidden,
                  let owned = purchasesByIngredient[ingredient.persistentModelID]
            else { continue }

            let atRisk = owned.reduce(0) { $0 + valueAtRisk(of: $1, now: now, cutoff: cutoff) }
            totalAtRisk += atRisk

            if let row = row(for: ingredient, purchases: owned, atRisk: atRisk, now: now, calendar: calendar) {
                qualifying.append(row)
            }
        }

        guard !qualifying.isEmpty || totalAtRisk > 0 else { return nil }

        qualifying.sort {
            ShoppingSuggestions.isOrderedBefore(
                reasons: [$0.reason],
                name: $0.ingredient.name,
                otherReasons: [$1.reason],
                otherName: $1.ingredient.name
            )
        }
        let limit = max(rowLimit, 0)
        return NeedsAttention(
            rows: Array(qualifying.prefix(limit)),
            moreCount: max(qualifying.count - limit, 0),
            valueAtRisk: totalAtRisk
        )
    }

    private static func row(
        for ingredient: Ingredient,
        purchases: [IngredientPurchase],
        atRisk: Double,
        now: Date,
        calendar: Calendar
    ) -> Row? {
        let remaining = purchases.reduce(0) { $0 + $1.remainingAmount }
        let reasons = ShoppingSuggestions.reasons(
            for: ingredient,
            purchases: purchases,
            remaining: remaining,
            now: now,
            calendar: calendar
        )
        guard let reason = reasons.first else { return nil }

        let newest = purchases.max { $0.dateOfPurchase < $1.dateOfPurchase }
        let supplier = newest?.provider?.name
        return Row(
            ingredient: ingredient,
            reason: reason,
            stamp: stamp(for: reason),
            remaining: remaining,
            unit: ingredient.unit,
            supplierName: supplier?.isEmpty == false ? supplier : nil,
            lowStockThreshold: ingredient.lowStockThreshold,
            earliestExpired: purchases
                .filter { $0.remainingAmount > 0 }
                .compactMap(\.expiryDate)
                .filter { $0 < now }
                .min(),
            valueAtRisk: atRisk
        )
    }

    private static func valueAtRisk(of purchase: IngredientPurchase, now: Date, cutoff: Date?) -> Double {
        guard purchase.remainingAmount > 0, let expiry = purchase.expiryDate else { return 0 }
        guard expiry < now || (cutoff.map { expiry <= $0 } ?? false) else { return 0 }
        return purchase.remainingAmount * purchase.pricePerUnit
    }

    private static func stamp(for reason: ShoppingSuggestionReason) -> IngredientStockStamp {
        switch reason {
        case .out: .out
        case .expired: .expired
        case .low: .low
        case .expiring(let days): .expiresIn(days: days)
        }
    }
}
