import Foundation
import Observation
import StoreKit

/// What the thank-you screen says about iCloud sync.
enum ProSyncOutcome: Equatable {
    case startsOnRelaunch
    case isOff

    init(prefersOffline: Bool) {
        self = prefersOffline ? .isOff : .startsOnRelaunch
    }
}

enum ProUpgradeLayout {
    static let gridMinimumWidth: CGFloat = 480

    static func usesGrid(width: CGFloat) -> Bool {
        width >= gridMinimumWidth
    }
}

/// The wording and enablement of the upgrade sheet's purchase button, kept out
/// of the view body so it can be tested.
enum ProUpgradeButton {
    static func title(price: String?, state: ProPurchaseState) -> String {
        let verb = state == .failed ? "Try again" : "Unlock Pro"
        guard let price else { return verb }
        return "\(verb) · \(price)"
    }

    static func isEnabled(price: String?, state: ProPurchaseState, isRestoring: Bool = false) -> Bool {
        guard price != nil, !isRestoring else { return false }
        switch state {
        case .idle, .failed: return true
        case .purchasing, .pending: return false
        }
    }

    static func canRestore(isRestoring: Bool, state: ProPurchaseState) -> Bool {
        !isRestoring && state != .purchasing
    }
}

enum ProRestoreAlert: Equatable {
    case restored
    case failed(String)
    case nothingFound

    var title: String {
        switch self {
        case .restored: "Purchases restored"
        case .failed: "Couldn’t restore purchases"
        case .nothingFound: "Nothing to restore"
        }
    }

    var message: String {
        switch self {
        case .restored: "SoapWiz Pro is active for this Apple Account."
        case .failed(let message): message
        case .nothingFound: "No SoapWiz Pro purchase was found for this Apple Account."
        }
    }
}

/// Runs a restore and turns its result into an alert, for the upgrade sheet and
/// the Settings section alike.
@Observable
@MainActor
final class ProRestoreModel {
    private(set) var isRestoring = false
    var alert: ProRestoreAlert?

    /// `announcesSuccess` is off where a successful restore already shows
    /// itself, as the upgrade sheet switching to its thank-you state.
    func restore(using store: ProStore, announcesSuccess: Bool = true) async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await store.restore()
            if !store.isPro {
                alert = .nothingFound
            } else if announcesSuccess {
                alert = .restored
            }
        } catch StoreKitError.userCancelled {
            // The user backed out of the sign-in prompt; nothing to report.
        } catch {
            alert = .failed(error.localizedDescription)
        }
    }
}
