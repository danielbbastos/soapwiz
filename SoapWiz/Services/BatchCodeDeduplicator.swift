import Foundation
import OSLog
import SwiftData

/// Renumbers batches that ended up sharing a generated code.
///
/// A code's sequence is only unique on the device that made it. Two devices
/// making the same recipe on the same day while out of touch both produce
/// `LAV-260930-01`, and only find out when they sync. Rather than lengthen
/// every code with a per-device part, the clash is settled here, after the
/// fact: the batch made first keeps the code and each later one moves to the
/// next free sequence.
///
/// Like `DuplicateMerger`, this only works if every device reaches the same
/// answer without coordinating, so the order is taken from synced data alone —
/// when the batch was made — and the stem is read off the code rather than
/// recomputed in the local time zone. Two batches that can't be told apart by
/// that data are left sharing the code: a device guessing which to move could
/// guess differently from its peer, and the two would renumber each other's
/// pick forever.
///
/// Who keeps a code is settled that way; where the other batch moves to is
/// not. "The next free sequence" is read from the codes this device holds,
/// and an import can land in parts. A device that has only seen half of a
/// day's batches can move the loser onto a number the other half already
/// uses, and then, when that half arrives, move whichever of the two is
/// later — a batch that was never in the original clash. Every device still
/// ends on the same unique codes, but a code already on a label can change.
/// Accepted: it takes the same recipe made on several devices on the same day
/// while out of touch, and avoiding it means numbering losers outside the
/// day's sequence.
///
/// Only codes of the generated shape are moved. The forms refuse a code that
/// is already taken, so a clash in a maker's own numbering can only come from
/// two devices typing it independently — and that one is theirs to settle:
/// the batch screen warns about it, and nothing here renames it.
@MainActor
enum BatchCodeDeduplicator {
    private static let log = Logger(subsystem: "pt.tachyon.SoapWiz", category: "merge")

    /// Runs the pass and swallows a failure, having logged it. A clash left in
    /// place is still flagged on screen, and the next trigger tries again.
    static func resolveLoggingFailure(in context: ModelContext) {
        do {
            try resolve(in: context)
        } catch {
            log.error("Batch code deduplication failed: \(error, privacy: .public)")
        }
    }

    /// Renumbers every later batch in a group sharing a generated code, and
    /// returns how many were moved. Safe to call repeatedly — a second pass
    /// finds no groups and saves nothing.
    @discardableResult
    static func resolve(in context: ModelContext) throws -> Int {
        let batches = try context.fetch(FetchDescriptor<Batch>())
        let coded = batches.filter { !BatchCodeGenerator.normalized($0.code).isEmpty }
        let groups = Dictionary(grouping: coded) { BatchCodeGenerator.normalized($0.code) }
        var usedCodes = Set(groups.keys)
        var renumbered = 0

        // Sorted, so the sequences handed out don't depend on dictionary order.
        for code in groups.keys.sorted() {
            guard let group = groups[code], group.count > 1,
                  let stem = BatchCodeGenerator.generatedStem(of: code) else { continue }

            let oldestFirst = group.sorted { orderKey($0) < orderKey($1) }
            for (earlier, batch) in zip(oldestFirst, oldestFirst.dropFirst()) {
                guard orderKey(earlier) != orderKey(batch) else { continue }
                let next = BatchCodeGenerator.nextCode(in: stem, existingCodes: usedCodes)
                batch.code = next
                usedCodes.insert(BatchCodeGenerator.normalized(next))
                renumbered += 1
            }
        }

        guard renumbered > 0 else { return 0 }
        try context.save()
        log.notice("Renumbered \(renumbered, privacy: .public) batch code(s) that clashed.")
        return renumbered
    }

    /// What decides who keeps a contested code. The date settles it in
    /// practice; the rest only make the order total, from fields that are the
    /// same on every device.
    private static func orderKey(_ batch: Batch) -> (Date, String, Int, Double) {
        (batch.dateCreated, batch.recipeName, batch.batchCount, batch.totalCost)
    }
}
