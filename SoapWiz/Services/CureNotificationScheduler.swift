import Foundation

/// What the cure reminders need of a batch, read off it before scheduling.
struct CureSnapshot {
    let recipeName: String
    let code: String
    /// The start of the day the bars can be used; see `CureStatus.usableDate`.
    /// `nil` when the batch has no earlier usable day than its ready one.
    let usableDate: Date?
    /// The start of the day the cure ends; see `CureStatus.readyDate`.
    let readyDate: Date
}

/// The two moments in a cure worth a reminder: the bars reaching the shortest
/// recommended cure, and the cure the batch was given coming to an end.
enum CureMilestone: String, CaseIterable {
    case usable
    case ready

    func date(of batch: CureSnapshot) -> Date? {
        switch self {
        case .usable: batch.usableDate
        case .ready: batch.readyDate
        }
    }

    func content(names: [String]) -> (title: String, body: String) {
        let list = names.joined(separator: ", ")
        switch (self, names.count == 1) {
        case (.usable, true):
            return (title: "Batch Usable", body: "\(list) can be used now, and keeps improving until it's fully cured.")
        case (.usable, false):
            return (title: "\(names.count) Batches Usable",
                    body: "\(list) can be used now, and keep improving until they're fully cured.")
        case (.ready, true):
            return (title: "Batch Ready", body: "\(list) has finished curing.")
        case (.ready, false):
            return (title: "\(names.count) Batches Ready", body: "\(list) have finished curing.")
        }
    }
}

/// One reminder per milestone per day, at 9:00 that morning — batches
/// reaching the same milestone on the same day share it rather than arriving
/// as a burst. A day already past 9:00 gets none: the batch screens already
/// show where those batches are.
///
/// Every sync rebuilds the whole set from the store, so a batch whose cure is
/// shortened, lengthened or deleted needs nothing of its own here.
enum CureNotificationScheduler {
    /// Shared by both milestones, so cancelling by it clears every cure
    /// reminder.
    static let notificationPrefix = "cure-"
    static let hour = 9

    static func computeRequests(
        batches: [CureSnapshot],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ScheduledReminder] {
        CureMilestone.allCases.flatMap { milestone in
            requests(for: milestone, batches: batches, now: now, calendar: calendar)
        }
        .sorted { $0.fireDate < $1.fireDate }
    }

    private static func requests(
        for milestone: CureMilestone,
        batches: [CureSnapshot],
        now: Date,
        calendar: Calendar
    ) -> [ScheduledReminder] {
        let dated = batches.compactMap { batch in milestone.date(of: batch).map { (calendar.startOfDay(for: $0), batch) } }
        let byDay = Dictionary(grouping: dated, by: \.0)

        return byDay.compactMap { day, entries -> ScheduledReminder? in
            guard let fireDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                  fireDate > now else { return nil }
            let (title, body) = milestone.content(names: entries.map { displayName($0.1) }.sorted())
            return ScheduledReminder(
                identifier: "\(notificationPrefix)\(milestone.rawValue)-\(calendar.reminderDayKey(for: day))",
                fireDate: fireDate,
                title: title,
                body: body
            )
        }
    }

    /// The recipe name, with the code when there is one: two batches of the
    /// same recipe due on one day are otherwise indistinguishable.
    static func displayName(_ batch: CureSnapshot) -> String {
        let code = BatchCodeGenerator.trimmed(batch.code)
        return code.isEmpty ? batch.recipeName : "\(batch.recipeName) (\(code))"
    }
}
