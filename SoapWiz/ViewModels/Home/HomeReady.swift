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
struct HomeReady: HomeRowPaging {
    /// Only batches that became ready within this many calendar days are
    /// listed; older ones count as seen, so a first launch doesn't list every
    /// past batch.
    static let recentDays = 30

    let items: [HomeReadyItem]

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
