import SwiftUI

enum AppTab: Hashable {
    case inventory
    case recipes
    case history
    case settings
}

/// Cross-tab navigation state: which tab is selected and the History tab's
/// stack path. Lets flows that end in another tab (creating a batch from a
/// recipe) land the user there directly.
@Observable
@MainActor
final class AppNavigation {
    var selectedTab: AppTab = .inventory
    var historyPath = NavigationPath()

    /// Switches to the History tab showing `batch`'s detail screen, with the
    /// history list as the only screen underneath it.
    func showBatch(_ batch: Batch) {
        historyPath = NavigationPath([batch])
        selectedTab = .history
    }
}
