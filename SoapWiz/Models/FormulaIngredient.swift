import Foundation
import SwiftData

@Model
final class FormulaIngredient {
    var formula: Formula?
    var ingredient: Ingredient?
    var percentage: Double

    func amountForSize(_ size: Double) -> Double {
        size * percentage / 100
    }

    var costPerUnit: Double {
        guard let ingredient else { return 0 }
        return ingredient.batches
            .min(by: { ($0.expiryDate ?? .distantFuture) < ($1.expiryDate ?? .distantFuture) })?
            .pricePerUnit ?? 0
    }

    init(ingredient: Ingredient? = nil, percentage: Double) {
        self.ingredient = ingredient
        self.percentage = percentage
    }
}
