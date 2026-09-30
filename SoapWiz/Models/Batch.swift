import Foundation
import SwiftData

/// An immutable record of a production run: making `batchCount` copies of a
/// recipe, with the ingredients it consumed and what they cost snapshotted at
/// the time of making. The link back to `Recipe` is soft (`.nullify`) so a batch
/// survives the recipe being edited or deleted — its `recipeName` and line items
/// are stored copies, not live reads. What the user adds afterwards — the code
/// and the log — sits beside that record and never changes it.
@Model
final class Batch {
    // Inverse and `.nullify` delete rule are declared on `Recipe.batches`, so a
    // deleted recipe drops this link instead of taking the batch with it.
    var recipe: Recipe?

    /// What goes on the label, so a bar sold can be traced back to this run —
    /// `LAV-260930-01` by default, see `BatchCodeGenerator`. Editable
    /// afterwards, for makers with a numbering scheme of their own. The forms
    /// refuse a code another batch carries, but two devices can still hand out
    /// the same one, so it can't serve as identity.
    var code: String = ""
    /// Recipe name as it was when the batch was made.
    var recipeName: String = ""
    var dateCreated: Date = Date.now
    var batchCount: Int = 0
    var totalCost: Double = 0
    /// Whether the batch was made with inventory tracking on. Snapshotted rather
    /// than read from `AppSettings`, so an untracked batch keeps reading as
    /// uncosted after tracking is switched back on.
    var tracksInventory: Bool = true

    /// Optional for CloudKit; read and write through `lineItems`. Neither name is
    /// usable in `#Predicate` — see `ModelContainerFactory.schema`.
    @Relationship(deleteRule: .cascade, originalName: "lineItems", inverse: \BatchLineItem.batch)
    var lineItemsStorage: [BatchLineItem]? = []

    var lineItems: [BatchLineItem] {
        get { lineItemsStorage ?? [] }
        set { lineItemsStorage = newValue }
    }

    /// The notes and photos recorded as the batch progresses. Cascades from the
    /// batch alone, so the log outlives the recipe and ingredients exactly as
    /// the batch does.
    ///
    /// Optional for CloudKit; read and write through `logEntries`. Neither name
    /// is usable in `#Predicate` — see `ModelContainerFactory.schema`.
    @Relationship(deleteRule: .cascade, inverse: \BatchLogEntry.batch)
    var logEntriesStorage: [BatchLogEntry]? = []

    var logEntries: [BatchLogEntry] {
        get { logEntriesStorage ?? [] }
        set { logEntriesStorage = newValue }
    }

    init(
        recipe: Recipe?,
        code: String = "",
        recipeName: String,
        dateCreated: Date = .now,
        batchCount: Int,
        totalCost: Double = 0,
        tracksInventory: Bool = true
    ) {
        self.recipe = recipe
        self.code = code
        self.recipeName = recipeName
        self.dateCreated = dateCreated
        self.batchCount = batchCount
        self.totalCost = totalCost
        self.tracksInventory = tracksInventory
    }
}
