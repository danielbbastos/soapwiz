import Foundation
import SwiftData

/// Display logic for the batch history list and batch detail. Everything here
/// reads the snapshot persisted at creation — never the live recipe or
/// inventory — so history stays immutable.
enum BatchHistoryViewModel {
    /// Newest first, the order the history list displays.
    static func sortedNewestFirst(_ batches: [Batch]) -> [Batch] {
        batches.sorted { $0.dateCreated > $1.dateCreated }
    }

    /// The batches a search for `query` should show: those whose code or recipe
    /// name contains it. A blank query shows everything.
    static func filtered(_ batches: [Batch], matching query: String) -> [Batch] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return batches }
        return batches.filter {
            $0.code.localizedCaseInsensitiveContains(query)
                || $0.recipeName.localizedCaseInsensitiveContains(query)
        }
    }

    /// The batch's code as shown on its own, with a dash standing in for a
    /// batch that has none yet — one synced in from a build that predates
    /// codes, until the next backfill pass reaches it.
    static func displayCode(of batch: Batch) -> String {
        let code = BatchCodeGenerator.trimmed(batch.code)
        return code.isEmpty ? "—" : code
    }

    /// Line items are unordered in SwiftData; display them alphabetically.
    static func sortedLineItems(of batch: Batch) -> [BatchLineItem] {
        batch.lineItems.sorted { $0.ingredientName < $1.ingredientName }
    }

    /// Log entries are unordered in SwiftData; display them oldest first, so
    /// the log reads as the batch went. `persistentModelID` cannot break a tie
    /// — it isn't comparable — so entries sharing a date fall back to their
    /// text, which keeps the order from shuffling between redraws.
    static func sortedLogEntries(of batch: Batch) -> [BatchLogEntry] {
        batch.logEntries.sorted {
            $0.date == $1.date ? $0.text < $1.text : $0.date < $1.date
        }
    }

    /// Nil for a batch made without inventory tracking: it recorded no cost, so
    /// there is nothing to divide — a zero would read as "this batch was free".
    static func costPerBatch(of batch: Batch) -> Double? {
        guard batch.tracksInventory else { return nil }
        guard batch.batchCount > 0 else { return 0 }
        return batch.totalCost / Double(batch.batchCount)
    }
}
