import Foundation
import SwiftData

/// One purchase a line item drew from under FIFO, snapshotted: the batch must
/// stay correct even if the purchase is later edited, depleted, or deleted, so
/// this stores copied values rather than a live link.
struct BatchPurchaseDraw: Codable, Hashable {
    /// Lot identifier of the purchase drawn from, as it was at the time.
    var purchaseBadge: String
    /// Amount drawn from this purchase, in the ingredient's inventory unit.
    var amountDrawn: Double
    /// Price per inventory unit paid for this purchase.
    var pricePerUnit: Double
    /// `amountDrawn * pricePerUnit`.
    var cost: Double
}

/// A single ingredient consumed by a `Batch`, snapshotted. Amounts are in the
/// ingredient's own inventory unit (converted from the recipe unit at the time
/// of making), and the cost is the sum of what each drawn purchase charged.
@Model
final class BatchLineItem {
    var batch: Batch?

    // Inverse and `.nullify` delete rule are declared on `Ingredient.batchLineItems`,
    // so a deleted ingredient drops this link instead of taking the line item with it.
    var ingredient: Ingredient?

    /// Ingredient name as it was when the batch was made.
    var ingredientName: String
    /// Amount consumed, in the ingredient's inventory unit.
    var amountConsumed: Double
    /// The ingredient's inventory unit.
    var unit: String
    var cost: Double
    /// Which purchases this amount drew from, oldest first.
    var draws: [BatchPurchaseDraw]

    init(
        ingredient: Ingredient?,
        ingredientName: String,
        amountConsumed: Double,
        unit: String,
        cost: Double,
        draws: [BatchPurchaseDraw]
    ) {
        self.ingredient = ingredient
        self.ingredientName = ingredientName
        self.amountConsumed = amountConsumed
        self.unit = unit
        self.cost = cost
        self.draws = draws
    }
}
