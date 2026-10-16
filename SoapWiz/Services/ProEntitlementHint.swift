import Foundation

/// The last entitlement StoreKit reported on this device.
///
/// Read at launch as a hint before StoreKit answers (store selection, a later
/// sub-issue), and rewritten on every refresh. Never proof of ownership: only
/// StoreKit is.
///
/// `nonisolated` for the same reason as `SyncPreference`: a typed view over
/// `UserDefaults`, constructible from a default argument.
nonisolated struct ProEntitlementHint {
    private enum Key {
        static let isPro = "pro.lastKnownIsPro"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isPro: Bool {
        get { defaults.bool(forKey: Key.isPro) }
        nonmutating set { defaults.set(newValue, forKey: Key.isPro) }
    }
}
