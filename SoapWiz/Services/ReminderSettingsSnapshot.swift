import Foundation

/// The settings that decide which reminders are scheduled. Two snapshots differ
/// exactly when a sync could have something new to do, so a change from a
/// CloudKit import or a restore can be told apart from one that leaves the
/// reminders as they were.
struct ReminderSettingsSnapshot: Equatable {
    var expiryNotificationsEnabled: Bool
    var cureNotificationsEnabled: Bool
    var tracksInventory: Bool

    init(expiryNotificationsEnabled: Bool, cureNotificationsEnabled: Bool, tracksInventory: Bool) {
        self.expiryNotificationsEnabled = expiryNotificationsEnabled
        self.cureNotificationsEnabled = cureNotificationsEnabled
        self.tracksInventory = tracksInventory
    }

    init(settings: AppSettings) {
        self.init(
            expiryNotificationsEnabled: settings.expiryNotificationsEnabled,
            cureNotificationsEnabled: settings.cureNotificationsEnabled,
            tracksInventory: settings.tracksInventory
        )
    }

    /// Read from the canonical record, with the stored defaults when there is none.
    init(records: [AppSettings]) {
        self.init(settings: AppSettings.canonical(from: records) ?? AppSettings())
    }
}
