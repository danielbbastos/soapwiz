import Foundation
import Observation

/// Why the upgrade sheet was opened, shown as a line above the benefits.
enum ProUpgradeReason: Hashable {
    case recipeLimit
    case customIngredientLimit
    case sync
    case collections
    case reminders

    var message: String {
        switch self {
        case .recipeLimit:
            "You have \(FreeTierLimits.recipeCap) recipes, the most the free version keeps. Pro removes the limit."
        case .customIngredientLimit:
            "You have \(FreeTierLimits.customIngredientCap) custom ingredients, the most the free version keeps. Pro removes the limit."
        case .sync:
            "iCloud sync is part of SoapWiz Pro."
        case .collections:
            "Collections are part of SoapWiz Pro."
        case .reminders:
            "Reminders are part of SoapWiz Pro."
        }
    }
}

/// One showing of the upgrade sheet. A fresh `id` per request makes a second
/// request replace the first rather than being ignored.
struct ProUpgradeRequest: Identifiable, Equatable {
    let id = UUID()
    let reason: ProUpgradeReason?
}

/// Lets any screen open the upgrade sheet.
///
/// A sheet can't present over another sheet's presenter, so the sheet is
/// attached by hosts: the root, and every sheet or cover an upgrade can be
/// asked from. Hosts register in the order they appear and only the topmost
/// one binds the sheet, so it comes up over whatever is open.
@Observable
@MainActor
final class ProUpgradePresenter {
    private(set) var request: ProUpgradeRequest?

    /// Changes each time the sheet asks to take the user to Settings, which
    /// `ContentView` follows by switching tab.
    private(set) var settingsRequest: UUID?

    /// The registered hosts, bottom first.
    private(set) var hostIDs: [UUID] = []

    var topHostID: UUID? { hostIDs.last }

    func registerHost(_ id: UUID) {
        hostIDs.removeAll { $0 == id }
        hostIDs.append(id)
    }

    /// Removes the host wherever it sits: a lower host can leave while one
    /// above it is still up, and the ones above stay.
    func unregisterHost(_ id: UUID) {
        hostIDs.removeAll { $0 == id }
    }

    func isTopHost(_ id: UUID) -> Bool {
        topHostID == id
    }

    /// Only the root host can take the user to Settings: from a sheet over a
    /// form, closing the sheet to switch tabs would throw the form away.
    func isRootHost(_ id: UUID) -> Bool {
        hostIDs.first == id
    }

    func present(reason: ProUpgradeReason? = nil) {
        request = ProUpgradeRequest(reason: reason)
    }

    func dismiss() {
        request = nil
    }

    func dismissToSettings() {
        request = nil
        settingsRequest = UUID()
    }
}
