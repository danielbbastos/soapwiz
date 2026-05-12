import Foundation
import SwiftData

@Model
final class Ingredient {
    var name: String
    var category: IngredientCategory?
    var unit: QuantityUnit?

    @Relationship(deleteRule: .cascade, inverse: \IngredientBatch.ingredient)
    var batches: [IngredientBatch] = []

    var totalRemaining: Double {
        batches.reduce(0) { $0 + $1.remainingAmount }
    }

    var nearestUpcomingExpiry: Date? {
        let now = Date.now
        guard let cutoff = Calendar.current.date(byAdding: .month, value: 1, to: now) else { return nil }
        return batches
            .compactMap(\.expiryDate)
            .filter { $0 > now && $0 <= cutoff }
            .min()
    }

    init(name: String, category: IngredientCategory? = nil, unit: QuantityUnit? = nil) {
        self.name = name
        self.category = category
        self.unit = unit
    }
}
