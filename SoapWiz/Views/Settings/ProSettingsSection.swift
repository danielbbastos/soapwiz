import SwiftUI
import SwiftData

/// Whether the user owns Pro, how close they are to the free limits, and the
/// way to buy or restore it.
struct ProSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ProStore.self) private var proStore
    @Environment(ProUpgradePresenter.self) private var presenter

    @State private var restoreModel = ProRestoreModel()
    @State private var recipeCount = 0
    @State private var customIngredientCount = 0

    var body: some View {
        Section {
            if proStore.isPro {
                statusRow(word: "Pro", tone: .amber, glyph: "checkmark")
                    .ledgerSheetRow(position: .first)
                restoreRow
                    .ledgerSheetRow(position: .last)
            } else {
                statusRow(word: "Free", tone: .neutral, glyph: nil)
                    .ledgerSheetRow(position: .first)
                limitRow("Recipes", count: recipeCount, cap: FreeTierLimits.recipeCap)
                    .ledgerSheetRow(position: .middle)
                limitRow(
                    "Custom ingredients",
                    count: customIngredientCount,
                    cap: FreeTierLimits.customIngredientCap
                )
                .ledgerSheetRow(position: .middle)
                Button {
                    presenter.present()
                } label: {
                    HStack {
                        Text("Upgrade to Pro")
                            .fontWeight(.semibold)
                        Spacer(minLength: 8)
                        if let price = proStore.displayPrice {
                            Text(price)
                        }
                    }
                    .foregroundStyle(Color.amberText)
                }
                .ledgerSheetRow(position: .middle)
                restoreRow
                    .ledgerSheetRow(position: .last)
            }
        } header: {
            // The List's first-header inset leaves the ornament lower than
            // centred; it clamps this negative padding to about 7pt up.
            VStack(alignment: .leading, spacing: 12) {
                HoneyLedgerOrnament()
                    .padding(.top, -10)
                HoneyLedgerSectionLabel("SoapWiz Pro")
            }
        } footer: {
            HoneyLedgerFooter(proStore.isPro ? Self.proFooter : Self.freeFooter)
        }
    }

    static let freeFooter = "One payment, no subscription. Pro adds unlimited recipes and custom "
        + "ingredients, iCloud sync, collections and reminders."
    static let proFooter = "Bought once. Yours on every device signed in to the same Apple Account."

    /// Always present, so it alone carries the modifiers that must run once
    /// for the section; on the `Section` they would fan out to every row.
    private func statusRow(word: String, tone: StatusStampTone, glyph: String?) -> some View {
        HoneyLedgerLabeledRow("Status") {
            StatusStamp(word: word, tone: tone, glyph: glyph)
        }
        .proRestoreAlert(restoreModel)
        .task {
            await proStore.refreshIfStale()
            await proStore.loadPrice()
        }
        .task { refreshCounts() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            refreshCounts()
        }
    }

    private func limitRow(_ title: String, count: Int, cap: Int) -> some View {
        HoneyLedgerLabeledRow(title) {
            Text("\(count) of \(cap)")
                .monospacedDigit()
                .foregroundStyle(count >= cap ? Color.danger : Color.inkSoft)
        }
    }

    private var restoreRow: some View {
        Button {
            Task { await restoreModel.restore(using: proStore) }
        } label: {
            HStack {
                Text("Restore purchases")
                    .foregroundStyle(Color.amberText)
                Spacer(minLength: 8)
                if restoreModel.isRestoring {
                    ProgressView()
                }
            }
        }
        .disabled(!ProUpgradeButton.canRestore(
            isRestoring: restoreModel.isRestoring,
            state: proStore.purchaseState
        ))
    }

    private func refreshCounts() {
        recipeCount = (try? FreeTierLimits.recipeCount(in: modelContext)) ?? 0
        customIngredientCount = (try? FreeTierLimits.customIngredientCount(in: modelContext)) ?? 0
    }
}
