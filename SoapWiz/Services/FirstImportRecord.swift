import Foundation

/// Whether this device has finished a CloudKit import successfully.
///
/// Per device and never synced: it describes this device's own first sync,
/// which is the only one long enough to warrant a notice. A device that has
/// imported once only ever catches up in short bursts after that.
///
/// `nonisolated` for the same reason as `SyncPreference`: a typed view over
/// `UserDefaults`, constructible from a default argument.
nonisolated struct FirstImportRecord {
    private enum Key {
        static let completed = "pt.tachyon.SoapWiz.completedFirstImport"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isCompleted: Bool {
        defaults.bool(forKey: Key.completed)
    }

    func markCompleted() {
        defaults.set(true, forKey: Key.completed)
    }
}
