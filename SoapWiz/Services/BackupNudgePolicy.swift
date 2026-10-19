import Foundation

/// Decides whether the History tab shows the backup reminder card.
///
/// It shows at most every 30 days after the latest of the last export, the last
/// dismissal and the first time the device was eligible. The first eligible
/// launch only records that date, so a new user isn't nudged on day one. Never
/// with a cloud copy, in the tour sandbox, or with no batches.
nonisolated enum BackupNudgePolicy {
    static let intervalDays = 30

    struct Context {
        var hasCloudCopy: Bool
        var isTourSandbox: Bool
        var batchCount: Int

        var isEligible: Bool {
            !hasCloudCopy && !isTourSandbox && batchCount > 0
        }
    }

    static func hasCloudCopy(_ activeStore: ModelContainerFactory.ActiveStore?) -> Bool {
        activeStore == .mirrored
    }

    static func shouldShow(
        _ context: Context,
        state: BackupNudgeState,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard context.isEligible, let firstEligible = state.firstEligibleDate else { return false }
        let latest = max(firstEligible, state.lastExportDate ?? .distantPast, state.lastDismissDate ?? .distantPast)
        guard let due = calendar.date(byAdding: .day, value: intervalDays, to: latest) else { return false }
        return now >= due
    }

    static func recordFirstEligibleIfNeeded(_ context: Context, state: BackupNudgeState, now: Date) {
        guard context.isEligible, state.firstEligibleDate == nil else { return }
        state.firstEligibleDate = now
    }
}
