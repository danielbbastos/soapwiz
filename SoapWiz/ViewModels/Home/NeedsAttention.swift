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

    /// The two sets the card is drawn from, without building any rows, so the
    /// Inventory filters can use them and never disagree with the card.
    /// `attention` is every ingredient the card would list, before the row
    /// limit caps it. `expiring` is the ingredients with stock left that
    /// expires within the next month, priced or not; `valueAtRisk` only counts
    /// the priced part of it.
    static func ingredientSets(
        ingredients: [Ingredient],
        purchases: [IngredientPurchase],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> (attention: Set<PersistentIdentifier>, expiring: Set<PersistentIdentifier>) {
        var attention: Set<PersistentIdentifier> = []
        var expiring: Set<PersistentIdentifier> = []
        evaluate(ingredients: ingredients, purchases: purchases, now: now, calendar: calendar) { ingredient, owned, _, isExpiring in
            let id = ingredient.persistentModelID
            if isExpiring { expiring.insert(id) }
            let remaining = owned.reduce(0) { $0 + $1.remainingAmount }
            if reason(for: ingredient, purchases: owned, remaining: remaining, now: now, calendar: calendar) != nil {
                attention.insert(id)
            }
        }
        return (attention, expiring)
    }

    static func make(
        ingredients: [Ingredient],
        purchases: [IngredientPurchase],
        tracksInventory: Bool,
        now: Date = .now,
        calendar: Calendar = .current,
        rowLimit: Int = 4
    ) -> NeedsAttention? {
        guard tracksInventory else { return nil }

        var qualifying: [Row] = []
        var totalAtRisk = 0.0
        evaluate(ingredients: ingredients, purchases: purchases, now: now, calendar: calendar) { ingredient, owned, atRisk, _ in
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

    /// Walks the listed ingredients that have purchases, with each one's
    /// purchases, the value at risk in them and whether any is expiring.
    private static func evaluate(
        ingredients: [Ingredient],
        purchases: [IngredientPurchase],
        now: Date,
        calendar: Calendar,
        visit: (Ingredient, [IngredientPurchase], Double, Bool) -> Void
    ) {
        var purchasesByIngredient: [PersistentIdentifier: [IngredientPurchase]] = [:]
        for purchase in purchases {
            guard let id = purchase.ingredient?.persistentModelID else { continue }
            purchasesByIngredient[id, default: []].append(purchase)
        }

        let cutoff = calendar.date(byAdding: .month, value: 1, to: now)
        for ingredient in ingredients {
            guard !ingredient.isHidden,
                  let owned = purchasesByIngredient[ingredient.persistentModelID]
            else { continue }
            let atRisk = owned.reduce(0) { $0 + valueAtRisk(of: $1, now: now, cutoff: cutoff) }
            let isExpiring = owned.contains { isExpiringInWindow($0, now: now, cutoff: cutoff) }
            visit(ingredient, owned, atRisk, isExpiring)
        }
    }

    private static func reason(
        for ingredient: Ingredient,
        purchases: [IngredientPurchase],
        remaining: Double,
        now: Date,
        calendar: Calendar
    ) -> ShoppingSuggestionReason? {
        return ShoppingSuggestions.reasons(
            for: ingredient,
            purchases: purchases,
            remaining: remaining,
            now: now,
            calendar: calendar
        ).first
    }

    private static func row(
        for ingredient: Ingredient,
        purchases: [IngredientPurchase],
        atRisk: Double,
        now: Date,
        calendar: Calendar
    ) -> Row? {
        let remaining = purchases.reduce(0) { $0 + $1.remainingAmount }
        guard let reason = reason(
            for: ingredient,
            purchases: purchases,
            remaining: remaining,
            now: now,
            calendar: calendar
        ) else { return nil }

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

    private static func isExpiringInWindow(_ purchase: IngredientPurchase, now: Date, cutoff: Date?) -> Bool {
        guard purchase.remainingAmount > 0, let expiry = purchase.expiryDate, let cutoff else { return false }
        return expiry >= now && expiry <= cutoff
    }

    private static func valueAtRisk(of purchase: IngredientPurchase, now: Date, cutoff: Date?) -> Double {
        guard isExpiringInWindow(purchase, now: now, cutoff: cutoff) else { return 0 }
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
