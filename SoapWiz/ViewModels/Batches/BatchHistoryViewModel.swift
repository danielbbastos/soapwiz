import Foundation
import SwiftData

/// Display logic for the batch history list and batch detail. Everything here
/// reads the snapshot persisted at creation — never the live recipe or
/// inventory — so history stays immutable.
@Observable
final class BatchHistoryViewModel {
    /// Newest first, matching the `@Query` sort used by the history list.
    static func sortedNewestFirst(_ batches: [Batch]) -> [Batch] {
        batches.sorted { $0.dateCreated > $1.dateCreated }
    }

    /// Line items are unordered in SwiftData; display them alphabetically.
    static func sortedLineItems(of batch: Batch) -> [BatchLineItem] {
        batch.lineItems.sorted { $0.ingredientName < $1.ingredientName }
    }

    static func costPerBatch(of batch: Batch) -> Double {
        guard batch.batchCount > 0 else { return 0 }
        return batch.totalCost / Double(batch.batchCount)
    }
}
