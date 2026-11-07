import Foundation

/// Escape hatch for exercising Pro screens where no StoreKit purchase exists — a
/// simulator launched with `simctl`. A release build can't enable it.
///
/// Opt-in via a launch argument rather than on whenever `DEBUG` is set. A debug
/// build on a device that owns Pro has to keep reading the real entitlement,
/// otherwise the purchase path silently stops being tested there.
///
/// It only changes what `ProStore.isPro` shows. The stored entitlement hint and
/// the store selection never see it, so a run with this argument stays on the
/// local store and cannot sync test data into an iCloud account.
///
/// Set it in a scheme's run arguments, or pass it to `simctl launch`.
enum ProDebugOverride {
#if DEBUG
    static let launchArgument = "-SoapWizDebugPro"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
#else
    static var isEnabled: Bool { false }
#endif
}
