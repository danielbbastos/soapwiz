import Foundation
import SwiftData

@Model
final class Ingredient {
    var name: String
    var code: String = ""
    var category: IngredientCategory?
    var unit: String

    var lowStockThreshold: Double?
    var sapValue: Double?
    var density: Double?

    @Relationship(deleteRule: .cascade, inverse: \IngredientBatch.ingredient)
    var batches: [IngredientBatch] = []

    @Relationship(deleteRule: .cascade, inverse: \RecipeIngredient.ingredient)
    var recipeIngredients: [RecipeIngredient] = []

    var totalRemaining: Double {
        batches.reduce(0) { $0 + $1.remainingAmount }
    }

    var isLowStock: Bool {
        guard let threshold = lowStockThreshold else { return false }
        return totalRemaining <= threshold
    }

    var hasExpiredBatch: Bool {
        let now = Date.now
        return batches.contains { ($0.expiryDate ?? .distantFuture) < now }
    }

    var nearestUpcomingExpiry: Date? {
        let now = Date.now
        guard let cutoff = Calendar.current.date(byAdding: .month, value: 1, to: now) else { return nil }
        return batches
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
