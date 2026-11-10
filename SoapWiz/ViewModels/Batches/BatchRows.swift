import Foundation
import SwiftData

/// Every batch, newest first, kept apart from `@Query`.
///
/// Batches aren't duplicated when a device joins an account, so an import
/// finishing doesn't wait for the duplicate merge. `settlingMerge` still
/// matters: the merge backfills and dedupes batch codes. Watches `Batch` and
/// `BatchLineItem`.
typealias BatchRows = ModelRows<Batch>

extension ModelRows where Model == Batch {
    convenience init(
        context: ModelContext,
        importTimeout: Duration = .seconds(120),
        pruneInterval: Duration = .seconds(1),
        fetchBatches: @escaping @MainActor (ModelContext) throws -> [Batch] = BatchRows.fetchAll(in:)
    ) {
        self.init(
            context: context,
            watchedEntities: [Schema.entityName(for: Batch.self), Schema.entityName(for: BatchLineItem.self)],
            logCategory: "batches",
            importTimeout: importTimeout,
            pruneInterval: pruneInterval,
            fetch: fetchBatches
        )
    }

    var batches: [Batch] { rows }

    @discardableResult
    func refreshIfBatchesChanged() -> Bool {
        refreshIfChanged()
    }

    /// Every batch, newest first. Injected only so a test can count the fetches or make them fail.
    static func fetchAll(in context: ModelContext) throws -> [Batch] {
        try context.fetch(FetchDescriptor<Batch>(sortBy: [SortDescriptor(\Batch.dateCreated, order: .reverse)]))
    }
}
