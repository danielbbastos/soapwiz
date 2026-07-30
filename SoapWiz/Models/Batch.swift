import Foundation
import SwiftData

/// An immutable record of a production run: making `batchCount` copies of a
/// recipe, with the ingredients it consumed and what they cost snapshotted at
/// the time of making. The link back to `Recipe` is soft (`.nullify`) so a batch
/// survives the recipe being edited or deleted — its `recipeName` and line items
/// are stored copies, not live reads.
@Model
final class Batch {
    // Inverse and `.nullify` delete rule are declared on `Recipe.batches`, so a
    // deleted recipe drops this link instead of taking the batch with it.
    var recipe: Recipe?

    /// Recipe name as it was when the batch was made.
    var recipeName: String = ""
    var dateCreated: Date = Date.now
    var batchCount: Int = 0
    var totalCost: Double = 0

    /// Optional for CloudKit; read and write through `lineItems`. Neither name is
    /// usable in `#Predicate` — see `ModelContainerFactory.schema`.
    @Relationship(deleteRule: .cascade, inverse: \BatchLineItem.batch)
    var lineItemsStorage: [BatchLineItem]? = []

    var lineItems: [BatchLineItem] {
        get { lineItemsStorage ?? [] }
        set { lineItemsStorage = newValue }
    }

    init(recipe: Recipe?, recipeName: String, dateCreated: Date = .now, batchCount: Int, totalCost: Double = 0) {
        self.recipe = recipe
        self.recipeName = recipeName
        self.dateCreated = dateCreated
        self.batchCount = batchCount
        self.totalCost = totalCost
    }
}
