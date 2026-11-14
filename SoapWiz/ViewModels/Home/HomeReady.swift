import Foundation
import SwiftData

/// One batch in Home's Ready to use card.
struct HomeReadyItem {
    let batch: Batch
    let readyDate: Date
}

/// The batches that finished curing and that the user hasn't yet acknowledged
/// on Home, most recently ready first. Computed from the batches, never
/// stored.
struct HomeReady {
    /// Only batches that became ready within this many calendar days are
    /// listed; older ones count as seen, so a first launch doesn't list every
    /// past batch.
    static let recentDays = 30

    /// Rows the card shows before "Show more".
    static let collapsedRowLimit = 4

    /// Rows the card shows at most once expanded; the rest are left to History.
    static let expandedRowLimit = 10

    let items: [HomeReadyItem]

    var count: Int { items.count }

    /// Whether there are more batches than the collapsed card shows.
    var canExpand: Bool { count > Self.collapsedRowLimit }

    /// The batches the card lists: the latest four, or up to ten once expanded.
    func visibleItems(isExpanded: Bool) -> [HomeReadyItem] {
        Array(items.prefix(isExpanded && canExpand ? Self.expandedRowLimit : Self.collapsedRowLimit))
    }

    /// The batches the expanded card leaves to History: only past ten, and
    /// none while collapsed, where "Show more" comes first.
    func historyCount(isExpanded: Bool) -> Int {
        isExpanded ? max(0, count - Self.expandedRowLimit) : 0
    }

    init(batches: [Batch], now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let ready = batches.compactMap { batch -> HomeReadyItem? in
            let status = CureStatus(dateCreated: batch.dateCreated, cureDays: batch.cureDays, now: now, calendar: calendar)
            guard case .ready = status,
                  batch.readySeenAt == nil,
                  let readyDate = CureStatus.readyDate(
                      dateCreated: batch.dateCreated,
                      cureDays: batch.cureDays,
                      calendar: calendar
                  ),
                  let staleFrom = calendar.date(byAdding: .day, value: Self.recentDays, to: readyDate),
                  today < staleFrom
            else { return nil }
            return HomeReadyItem(batch: batch, readyDate: readyDate)
        }
        items = ready.sorted { $0.readyDate > $1.readyDate }
    }

    /// Marks `batches` as seen at `now` and saves. Skips batches already seen
    /// and any deleted meanwhile, which SwiftData must not be asked to read.
    static func markSeen(_ batches: [Batch], now: Date = .now, context: ModelContext) {
        var changed = false
        for batch in batches where !batch.isDeleted && batch.modelContext != nil && batch.readySeenAt == nil {
            batch.readySeenAt = now
            changed = true
        }
        if changed { context.saveLoggingFailure() }
    }
}
