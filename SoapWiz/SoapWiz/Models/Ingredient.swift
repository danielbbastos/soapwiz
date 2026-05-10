import Foundation
import SwiftData

@Model
final class Ingredient {
    var name: String
    var category: String
    var unit: String

    @Relationship(deleteRule: .cascade, inverse: \IngredientBatch.ingredient)
    var batches: [IngredientBatch] = []

    var totalRemaining: Double {
        batches.reduce(0) { $0 + $1.remainingAmount }
    }

    init(name: String, category: String, unit: String) {
        self.name = name
        self.category = category
        self.unit = unit
    }
}
