import Foundation
import SwiftData

/// Reports what has been written to the store since it was last asked.
///
/// SwiftData re-evaluates every `@Query` after each CloudKit mirroring event,
/// because CloudKit writes its own bookkeeping to the store whether or not a
/// model row changed. The store's persistent history tells those events apart:
/// an import that changed nothing leaves no transaction, and one that changed an
/// ingredient leaves a transaction naming it. A fetch is cheap (well under a
/// millisecond) when it starts from a token.
///
/// Each consumer owns its own cursor, so one asking doesn't consume what
/// another still has to see.
///
/// A cursor starts at the moment it is created. Fetching the whole history to
/// find the newest token would cost tens of milliseconds at launch, so until the
/// first transaction turns up it asks for those stamped after that moment, and
/// from then on for those after the newest token it has seen.
@MainActor
final class StoreHistoryCursor {
    private let context: ModelContext
    private var startedAt: Date
    private var lastToken: DefaultHistoryToken?

    init(context: ModelContext, startedAt: Date = .now) {
        self.context = context
        self.startedAt = startedAt
    }

    /// Every change made since the previous call, or since the cursor was
    /// created for the first call. Includes this process's own saves.
    ///
    /// Throws when the history can't be read. The cursor then starts over from
    /// now, so the failure is reported once; callers should treat it as "anything
    /// may have changed" and fall back to their safe behaviour.
    func changesSinceLastCheck() throws -> [HistoryChange] {
        let descriptor: HistoryDescriptor<DefaultHistoryTransaction>
        if let token = lastToken {
            descriptor = HistoryDescriptor(predicate: #Predicate { $0.token > token })
        } else {
            let start = startedAt
            descriptor = HistoryDescriptor(predicate: #Predicate { $0.timestamp > start })
        }
        do {
            let transactions = try context.fetchHistory(descriptor)
            // iOS 18 can't sort a history fetch, so take the newest explicitly
            // instead of relying on the order it happens to return.
            if let newest = transactions.map(\.token).max() {
                lastToken = newest
            }
            return transactions.flatMap(\.changes)
        } catch {
            lastToken = nil
            startedAt = .now
            throw error
        }
    }
}

extension HistoryChange {
    /// The entity of the row this change touched, as the schema names it.
    var entityName: String {
        switch self {
        case .insert(let change): change.changedPersistentIdentifier.entityName
        case .update(let change): change.changedPersistentIdentifier.entityName
        case .delete(let change): change.changedPersistentIdentifier.entityName
        @unknown default: ""
        }
    }
}
