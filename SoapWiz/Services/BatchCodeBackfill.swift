import Foundation
import OSLog
import SwiftData

/// Gives a code to every batch that has none: the ones made before SW-175, the
/// ones a backup written before it restores, and the ones a device still on an
/// older build syncs in.
///
/// Batches are coded oldest first, so a day's sequence follows the order they
/// were made in. A batch that already has a code is never touched, so a second
/// pass writes nothing.
///
/// Two devices backfilling the same history reach the same codes only when
/// they share a time zone and hold the same batches; otherwise the last one
/// to sync wins and `BatchCodeDeduplicator` settles any clash. One case is
/// accepted rather than solved: a device still on a build without the field
/// drops the codes it syncs, so once it updates, an empty code here can mean
/// "coded elsewhere" — and this pass writes a generated code over it, even
/// over one the user typed on the other device. Nothing on this device can
/// tell the two apart.
@MainActor
enum BatchCodeBackfill {
    private static let log = Logger(subsystem: "pt.tachyon.SoapWiz", category: "backfill")

    /// Runs the pass and swallows a failure, having logged it. A batch without a
    /// code shows a dash until the next pass, which is survivable; losing the
    /// launch to it would not be.
    static func fillMissingCodesLoggingFailure(in context: ModelContext) {
        do {
            try fillMissingCodes(in: context)
        } catch {
            log.error("Batch code backfill failed: \(error, privacy: .public)")
        }
    }

    /// Codes every batch that has none, and returns how many were coded.
    @discardableResult
    static func fillMissingCodes(in context: ModelContext, timeZone: TimeZone = .current) throws -> Int {
        let batches = try context.fetch(FetchDescriptor<Batch>())
        var usedCodes: Set<String> = []
        var uncoded: [Batch] = []
        for batch in batches {
            let code = BatchCodeGenerator.normalized(batch.code)
            if code.isEmpty {
                uncoded.append(batch)
            } else {
                usedCodes.insert(code)
            }
        }

        for batch in uncoded.sorted(by: { ($0.dateCreated, $0.recipeName) < ($1.dateCreated, $1.recipeName) }) {
            let code = BatchCodeGenerator.suggestedCode(
                recipeName: batch.recipeName,
                date: batch.dateCreated,
                existingCodes: usedCodes,
                timeZone: timeZone
            )
            batch.code = code
            usedCodes.insert(BatchCodeGenerator.normalized(code))
        }

        guard !uncoded.isEmpty else { return 0 }
        try context.save()
        log.notice("Filled \(uncoded.count, privacy: .public) missing batch code(s).")
        return uncoded.count
    }
}
