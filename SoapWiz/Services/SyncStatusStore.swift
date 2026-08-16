import Foundation

/// The small amount of sync state that has to outlive a launch.
///
/// Two facts need persisting, for opposite reasons. The last successful sync is
/// the only way a row can say something more useful than "Synced" — without a
/// date, "Synced" is indistinguishable from "Synced eleven days ago". And a
/// launch that fell back to a local store leaves no other trace: the next launch
/// may well succeed, and then nothing anywhere records that a stretch of the
/// user's data was written while mirroring was off. SW-100 needs exactly that
/// fact to decide whether those rows ever reached iCloud.
/// `nonisolated` in a module that defaults to `@MainActor`: this is a typed view
/// over `UserDefaults`, which is thread-safe, and it has to be constructible
/// from a default argument — those are evaluated outside the callee's isolation.
nonisolated struct SyncStatusStore {
    private enum Key {
        static let lastSuccessfulSync = "sync.lastSuccessfulSync"
        static let lastFallbackDate = "sync.lastLocalFallbackDate"
        static let lastFallbackReason = "sync.lastLocalFallbackReason"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastSuccessfulSync: Date? {
        get { defaults.object(forKey: Key.lastSuccessfulSync) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.lastSuccessfulSync) }
    }

    /// When mirroring was last requested and refused at launch, and why.
    var lastLocalFallback: (date: Date, reason: String)? {
        guard let date = defaults.object(forKey: Key.lastFallbackDate) as? Date else { return nil }
        return (date, defaults.string(forKey: Key.lastFallbackReason) ?? "")
    }

    /// Overwrites rather than accumulates: the most recent fallback is the one
    /// that bounds how far back the store might be out of step with iCloud.
    ///
    /// Nothing clears this. The record is deliberately durable — it is the only
    /// evidence that rows were written while mirroring was off, and SW-100 needs
    /// it to decide whether those rows ever exported. The UI stops mentioning it
    /// once a later sync moves data; see `SyncHealthMonitor.unresolvedFallback`.
    func recordLocalFallback(reason: String, at date: Date = .now) {
        defaults.set(date, forKey: Key.lastFallbackDate)
        defaults.set(reason, forKey: Key.lastFallbackReason)
    }
}
