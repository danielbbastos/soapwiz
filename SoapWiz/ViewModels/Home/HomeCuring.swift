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

    let items: [HomeCuringItem]

    var count: Int { items.count }

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
