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

/// Lets any screen open the one upgrade sheet attached at the root.
@Observable
@MainActor
final class ProUpgradePresenter {
    private(set) var request: ProUpgradeRequest?

    /// Changes each time the sheet asks to take the user to Settings, which
    /// `ContentView` follows by switching tab.
    private(set) var settingsRequest: UUID?

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
