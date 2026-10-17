import Foundation

/// When this device last exported a backup, last dismissed the reminder, and
/// first became eligible for it.
///
/// Device-only on purpose: a device without sync has no cloud copy to share
/// these dates with. `nonisolated` for the same reason as `ProEntitlementHint`:
/// a typed view over `UserDefaults`, constructible from a default argument.
nonisolated struct BackupNudgeState {
    private enum Key {
        static let lastExportDate = "backupNudge.lastExportDate"
        static let lastDismissDate = "backupNudge.lastDismissDate"
        static let firstEligibleDate = "backupNudge.firstEligibleDate"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastExportDate: Date? {
        get { date(forKey: Key.lastExportDate) }
        nonmutating set { store(newValue, forKey: Key.lastExportDate) }
    }

    var lastDismissDate: Date? {
        get { date(forKey: Key.lastDismissDate) }
        nonmutating set { store(newValue, forKey: Key.lastDismissDate) }
    }

    var firstEligibleDate: Date? {
        get { date(forKey: Key.firstEligibleDate) }
        nonmutating set { store(newValue, forKey: Key.firstEligibleDate) }
    }

    private func date(forKey key: String) -> Date? {
        defaults.object(forKey: key) as? Date
    }

    private func store(_ date: Date?, forKey key: String) {
        if let date {
            defaults.set(date, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
