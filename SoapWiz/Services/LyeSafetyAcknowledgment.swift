import Foundation

/// Whether the user has accepted the lye safety notice on this device.
///
/// Per device rather than synced through `AppSettings`. Syncing couldn't keep
/// the promise anyway — a new device can open a soap recipe before iCloud has
/// delivered the settings record — and a safety notice asked once more on a
/// second device or after a reinstall costs nothing worth a schema change.
///
/// `nonisolated` for the same reason as `SyncStatusStore`: a typed view over
/// `UserDefaults`, constructible from a default argument.
nonisolated struct LyeSafetyAcknowledgment {
    private enum Key {
        static let acknowledged = "safety.lyeNoticeAcknowledged"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isAcknowledged: Bool {
        defaults.bool(forKey: Key.acknowledged)
    }

    func acknowledge() {
        defaults.set(true, forKey: Key.acknowledged)
    }

    /// Only a soap recipe shows lye amounts, so only a soap recipe asks.
    func shouldPresent(makesSoap: Bool) -> Bool {
        makesSoap && !isAcknowledged
    }
}
