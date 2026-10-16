import SwiftUI

extension SettingsView {
    /// States why recipe import is or isn't on offer.
    ///
    /// The entry point on the Recipes tab stays hidden when the model can't run
    /// — a button that fails on tap is worse than no button. But hiding it
    /// silently leaves "Apple Intelligence is switched off" indistinguishable
    /// from "this feature doesn't exist", so the reason lives here.
    var recipeImportSection: some View {
        let availability = RecipeImportAvailability.current
        return Section {
            HoneyLedgerLabeledRow("Status") {
                Label(availability.statusText, systemImage: availability.statusSymbol)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(statusTint(for: availability))
            }
            .ledgerSheetRow(position: .only)
        } header: {
            HoneyLedgerSectionLabel("Recipe Import")
        } footer: {
            HoneyLedgerFooter(availability.settingsFooter)
        }
    }

    private func statusTint(for availability: RecipeImportAvailability) -> Color {
        if availability.isAvailable { return .success }
        return availability.isActionable ? .warning : .inkSoft
    }
}
