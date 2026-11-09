import Foundation
import SwiftData

/// Why an ingredient is on the shopping list's suggestions.
enum ShoppingSuggestionReason: Equatable {
    case out
    case expired
    case low
    case expiring(days: Int)

    var rank: Int {
        switch self {
        case .out: 0
        case .expired: 1
        case .low: 2
        case .expiring: 3
        }
    }
}

/// An ingredient worth buying again, with what the list row needs to say why and
/// where it was last bought.
struct ShoppingSuggestion: Identifiable, Equatable {
    let ingredient: Ingredient
    /// Most urgent first.
    let reasons: [ShoppingSuggestionReason]
    let remaining: Double
    let unit: String
    let lastPurchase: LastPurchase

    var id: PersistentIdentifier { ingredient.persistentModelID }
}

/// Computes the suggestions from one pass over every purchase.
///
/// Reading `ingredient.purchases` per ingredient is what `StockLevels` replaced,
/// so this groups the fetched purchases once and never touches the relationship.
enum ShoppingSuggestions {
    static func make(
        ingredients: [Ingredient],
        purchases: [IngredientPurchase],
        listedIngredientIDs: Set<PersistentIdentifier>,
        tracksInventory: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ShoppingSuggestion] {
        guard tracksInventory else { return [] }

        var purchasesByIngredient: [PersistentIdentifier: [IngredientPurchase]] = [:]
        for purchase in purchases {
            guard let id = purchase.ingredient?.persistentModelID else { continue }
            purchasesByIngredient[id, default: []].append(purchase)
        }

        var suggestions: [ShoppingSuggestion] = []
        for ingredient in ingredients {
            let id = ingredient.persistentModelID
            guard !ingredient.isHidden,
                  !listedIngredientIDs.contains(id),
                  let owned = purchasesByIngredient[id],
                  !isDismissed(ingredient, purchases: owned)
            else { continue }

            let remaining = owned.reduce(0) { $0 + $1.remainingAmount }
            let reasons = reasons(for: ingredient, purchases: owned, remaining: remaining, now: now, calendar: calendar)
            guard !reasons.isEmpty else { continue }

            let last = owned.max { $0.dateOfPurchase < $1.dateOfPurchase }.map(LastPurchase.init)
                ?? LastPurchase(quantity: nil, supplierName: nil, pricePerUnit: nil)
            suggestions.append(
                ShoppingSuggestion(
                    ingredient: ingredient,
                    reasons: reasons,
                    remaining: remaining,
                    unit: ingredient.unit,
                    lastPurchase: last
                )
            )
        }

        return suggestions.sorted(by: isOrderedBefore)
    }

    /// Hidden until a purchase dated after the dismissal arrives.
    private static func isDismissed(_ ingredient: Ingredient, purchases: [IngredientPurchase]) -> Bool {
        guard let dismissedAt = ingredient.shoppingSuggestionDismissedAt else { return false }
        return !purchases.contains { $0.dateOfPurchase > dismissedAt }
    }

    /// Only stock still on the shelf can expire, so a used-up purchase's date is
    /// ignored.
    static func reasons(
        for ingredient: Ingredient,
        purchases: [IngredientPurchase],
        remaining: Double,
        now: Date,
        calendar: Calendar
    ) -> [ShoppingSuggestionReason] {
        var result: [ShoppingSuggestionReason] = []

        let isOut = remaining <= 0
        if isOut {
            result.append(.out)
        }

        let expiries = purchases.filter { $0.remainingAmount > 0 }.compactMap(\.expiryDate)
        if expiries.contains(where: { $0 < now }) {
            result.append(.expired)
        }

        if !isOut, let threshold = ingredient.lowStockThreshold, remaining <= threshold {
            result.append(.low)
        }

        if !result.contains(.expired),
           let nearest = expiries.filter({ $0 >= now }).min(),
           case .expiresIn(let days)? = IngredientStockStamp.expiry(nearest, now: now, calendar: calendar) {
            result.append(.expiring(days: days))
        }

        return result.sorted { $0.rank < $1.rank }
    }

    private static func isOrderedBefore(_ lhs: ShoppingSuggestion, _ rhs: ShoppingSuggestion) -> Bool {
        isOrderedBefore(
            reasons: lhs.reasons,
            name: lhs.ingredient.name,
            otherReasons: rhs.reasons,
            otherName: rhs.ingredient.name
        )
    }

    static func isOrderedBefore(
        reasons: [ShoppingSuggestionReason],
        name: String,
        otherReasons: [ShoppingSuggestionReason],
        otherName: String
    ) -> Bool {
        guard let left = reasons.first, let right = otherReasons.first else { return false }
        if left.rank != right.rank {
            return left.rank < right.rank
        }
        if case .expiring(let leftDays) = left, case .expiring(let rightDays) = right, leftDays != rightDays {
            return leftDays < rightDays
        }
        return name.localizedStandardCompare(otherName) == .orderedAscending
    }
}
