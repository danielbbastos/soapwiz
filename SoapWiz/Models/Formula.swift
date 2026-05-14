import Foundation
import SwiftData

@Model
final class Formula {
    var name: String
    var lossPercentage: Double?

    @Relationship(deleteRule: .cascade, inverse: \FormulaIngredient.formula)
    var ingredients: [FormulaIngredient] = []

    @Relationship(deleteRule: .cascade, inverse: \ProductVariant.formula)
    var variants: [ProductVariant] = []

    @Relationship(deleteRule: .cascade, inverse: \ProductionRun.formula)
    var runs: [ProductionRun] = []

    init(name: String, lossPercentage: Double? = nil) {
        self.name = name
        self.lossPercentage = lossPercentage
    }
}
