import Foundation

/// The line under the iCloud section when the saved choice and the user's Pro
/// status call for a different store than the one this launch opened.
enum SyncRelaunchNotice {
    static func text(
        localCause: ModelContainerFactory.LocalStoreCause?,
        isPro: Bool,
        prefersOffline: Bool
    ) -> String? {
        let wantsLocal = StoreSelection.isOffline(isPro: isPro, prefersOffline: prefersOffline)
        guard wantsLocal != (localCause != nil) else { return nil }
        if wantsLocal {
            // A refund also lands here. The next launch goes local on its own
            // and the status row says why, so there is nothing to ask of the user.
            guard isPro else { return nil }
            return message(for: "turn off iCloud sync")
        }
        switch localCause {
        case .requiresPro: return message(for: "start iCloud sync")
        case .offlineByChoice, nil: return message(for: "turn iCloud sync back on")
        }
    }

    private static func message(for change: String) -> String {
        "Close SoapWiz from the app switcher and open it again to \(change)."
    }
}
