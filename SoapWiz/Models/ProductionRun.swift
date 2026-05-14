import Foundation
import SwiftData

@Model
final class ProductionRun {
    var formula: Formula?
    var variant: ProductVariant?
    var quantity: Int
    var date: Date
    var lossPercentage: Double

    @Relationship(deleteRule: .cascade, inverse: \ProductionIngredientDeduction.run)
    var deductions: [ProductionIngredientDeduction] = []

    init(
        formula: Formula? = nil,
        variant: ProductVariant? = nil,
        quantity: Int,
        date: Date = .now,
        lossPercentage: Double
    ) {
        self.formula = formula
        self.variant = variant
        self.quantity = quantity
        self.date = date
        self.lossPercentage = lossPercentage
    }
}
