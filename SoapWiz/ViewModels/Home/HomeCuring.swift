import Foundation

/// One batch in Home's Curing card.
struct HomeCuringItem {
    let batch: Batch
    let progress: Double
    let remaining: CureRemaining
    let readyDate: Date
    let isReadyThisWeek: Bool
}

/// The batches still curing, soonest ready first. Computed from the batches,
/// never stored.
struct HomeCuring {
    /// A batch ready within this many calendar days of today counts as ready
    /// this week.
    static let readySoonDays = 7

    /// Rows the card shows before "Show more".
    static let collapsedRowLimit = 4

    /// Rows the card shows at most once expanded; the rest are left to History.
    static let expandedRowLimit = 10

    let items: [HomeCuringItem]

    var count: Int { items.count }

    /// Whether there are more batches than the collapsed card shows.
    var canExpand: Bool { count > Self.collapsedRowLimit }

    /// The batches the card lists: the soonest four, or up to ten once expanded.
    func visibleItems(isExpanded: Bool) -> [HomeCuringItem] {
        Array(items.prefix(isExpanded && canExpand ? Self.expandedRowLimit : Self.collapsedRowLimit))
    }

    /// The batches the expanded card leaves to History: only past ten, and
    /// none while collapsed, where "Show more" comes first.
    func historyCount(isExpanded: Bool) -> Int {
        isExpanded ? max(0, count - Self.expandedRowLimit) : 0
    }

    var readyThisWeekCount: Int {
        items.filter(\.isReadyThisWeek).count
    }

    init(batches: [Batch], now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let curing = batches.compactMap { batch -> HomeCuringItem? in
            let status = CureStatus(dateCreated: batch.dateCreated, cureDays: batch.cureDays, now: now, calendar: calendar)
            guard case .curing(let remaining, let progress) = status,
                  let readyDate = CureStatus.readyDate(
                      dateCreated: batch.dateCreated,
                      cureDays: batch.cureDays,
                      calendar: calendar
                  ),
                  let daysLeft = calendar.dateComponents([.day], from: today, to: readyDate).day
            else { return nil }
            return HomeCuringItem(
                batch: batch,
                progress: progress,
                remaining: remaining,
                readyDate: readyDate,
                isReadyThisWeek: daysLeft <= Self.readySoonDays
            )
        }
        items = curing.sorted { $0.readyDate < $1.readyDate }
    }
}
