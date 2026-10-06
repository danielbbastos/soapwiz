import Foundation

/// Whether the user has turned iCloud sync off on this device.
///
/// Per device rather than in `AppSettings`: a synced setting can't reach a
/// device that has stopped syncing, and a device that turns sync off should
/// never switch another one off with it.
///
/// `nonisolated` for the same reason as `SyncStatusStore`: a typed view over
/// `UserDefaults`, constructible from a default argument.
nonisolated struct SyncPreference {
    private enum Key {
        static let usesOffline = "sync.usesOffline"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var usesOffline: Bool {
        get { defaults.bool(forKey: Key.usesOffline) }
        nonmutating set { defaults.set(newValue, forKey: Key.usesOffline) }
    }
}
