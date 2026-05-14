import Foundation
import SwiftData

@Model
final class ProductionIngredientDeduction {
    var run: ProductionRun?
    var ingredient: Ingredient?
    var batchId: PersistentIdentifier?
    var amountUsed: Double

    init(ingredient: Ingredient? = nil, batchId: PersistentIdentifier? = nil, amountUsed: Double) {
        self.ingredient = ingredient
        self.batchId = batchId
        self.amountUsed = amountUsed
    }
}
