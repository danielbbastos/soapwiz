import Foundation
import SwiftData

/// One month of the history list: every batch made in it, newest first.
struct BatchMonthSection: Identifiable {
    /// The first instant of the month, in the calendar the sections were built
    /// with.
    let month: Date
    let batches: [Batch]

    var id: Date { month }

    /// "September 2026", in the device's language. Always with the year:
    /// history runs across years, and a bare "April" is ambiguous a year later.
    var title: String {
        month.formatted(.dateTime.month(.wide).year())
    }
}

/// The figures under the History title, over every batch whatever the search is
/// narrowing the list to.
struct BatchCountSummary: Equatable {
    let total: Int
    let curing: Int

    /// Nil when there is nothing to count, so the line is left out.
    var line: String? {
        guard total > 0 else { return nil }
        // Plain `String(localized:)` leaves the agreement markup as it is: only
        // an attributed string resolves it.
        var parts = [String(AttributedString(localized: "^[\(total) batch](inflect: true)").characters)]
        if curing > 0 {
            parts.append(String(localized: "\(curing) curing"))
        }
        return parts.joined(separator: " · ")
    }
}

extension BatchCountSummary {
    init(counting batches: [Batch]) {
        self.init(
            total: batches.count,
            curing: batches.count {
                if case .curing = $0.cureStatus { true } else { false }
            }
        )
    }
}

/// Display logic for the batch history list and batch detail. Everything here
/// reads the snapshot persisted at creation — never the live recipe or
/// inventory — so history stays immutable.
enum BatchHistoryViewModel {
    /// Newest first, the order the history list displays.
    static func sortedNewestFirst(_ batches: [Batch]) -> [Batch] {
        batches.sorted { $0.dateCreated > $1.dateCreated }
    }

    /// Groups `batches` by the calendar month they were made in, newest month
    /// first and newest batch first within each. Months with no batches are
    /// left out rather than shown empty, so a search only lists the months it
    /// matched. `calendar` is injectable for tests; its time zone decides which
    /// month a batch made around midnight on the last day belongs to.
    static func monthSections(_ batches: [Batch], calendar: Calendar = .current) -> [BatchMonthSection] {
        let byMonth = Dictionary(grouping: batches) { batch in
            calendar.dateInterval(of: .month, for: batch.dateCreated)?.start ?? batch.dateCreated
        }
        return byMonth.keys.sorted(by: >).map { month in
            BatchMonthSection(month: month, batches: sortedNewestFirst(byMonth[month] ?? []))
        }
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

    /// What the photo viewer pages through when the photo at `tappedIndex` of
    /// an entry's sorted photos is tapped, and which page it opens on. A photo
    /// whose file hasn't arrived from iCloud yet has no data and is left out,
    /// so the tapped one is counted again among those that do. Nil when the
    /// tapped photo is one of those, or the index is out of range.
    static func viewerPages(_ images: [Data?], tappedIndex: Int) -> (images: [Data], startIndex: Int)? {
        guard images.indices.contains(tappedIndex), images[tappedIndex] != nil else { return nil }
        let startIndex = images[..<tappedIndex].count { $0 != nil }
        return (images.compactMap(\.self), startIndex)
    }

    /// Nil for a batch made without inventory tracking: it recorded no cost, so
    /// there is nothing to divide — a zero would read as "this batch was free".
    static func costPerBatch(of batch: Batch) -> Double? {
        guard batch.tracksInventory else { return nil }
        guard batch.batchCount > 0 else { return 0 }
        return batch.totalCost / Double(batch.batchCount)
    }
}
