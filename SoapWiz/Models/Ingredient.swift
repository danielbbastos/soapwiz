import Foundation
import SwiftData

@Model
final class Ingredient {
    var name: String = ""
    var code: String = ""
    var category: IngredientCategory?
    var unit: String = ""

    var lowStockThreshold: Double?
    var sapValue: Double?
    var kohSapValue: Double?
    var density: Double?
    var fattyAcidProfile: FattyAcidProfile?

    @Relationship(deleteRule: .cascade, inverse: \IngredientPurchase.ingredient)
    var purchases: [IngredientPurchase] = []

    @Relationship(deleteRule: .cascade, inverse: \RecipeIngredient.ingredient)
    var recipeIngredients: [RecipeIngredient] = []

    /// Batch line items that consumed this ingredient. Deleting the ingredient
    /// nullifies the line item's back-link (`.nullify`) rather than deleting it —
    /// batch history is an immutable record that must outlive the ingredient.
    @Relationship(deleteRule: .nullify, inverse: \BatchLineItem.ingredient)
    var batchLineItems: [BatchLineItem] = []

    /// Recipes using this ingredient as their NaOH lye. Deleting the ingredient
    /// nullifies the recipe's link rather than deleting the recipe.
    @Relationship(deleteRule: .nullify, inverse: \Recipe.lyeIngredient)
    var recipesUsingAsLye: [Recipe] = []

    /// Recipes using this ingredient as their KOH lye on the hybrid path.
    @Relationship(deleteRule: .nullify, inverse: \Recipe.kohLyeIngredient)
    var recipesUsingAsKOHLye: [Recipe] = []

    var totalRemaining: Double {
        purchases.reduce(0) { $0 + $1.remainingAmount }
    }

    var isLowStock: Bool {
        guard let threshold = lowStockThreshold else { return false }
        return totalRemaining <= threshold
    }

    var hasExpiredPurchase: Bool {
        let now = Date.now
        return purchases.contains { ($0.expiryDate ?? .distantFuture) < now }
    }

    var nearestUpcomingExpiry: Date? {
        let now = Date.now
        guard let cutoff = Calendar.current.date(byAdding: .month, value: 1, to: now) else { return nil }
        return purchases
            .compactMap(\.expiryDate)
            .filter { $0 > now && $0 <= cutoff }
            .min()
    }

    init(name: String, category: IngredientCategory? = nil, unit: String = "") {
        self.name = name
        self.category = category
        self.unit = unit
    }
}
