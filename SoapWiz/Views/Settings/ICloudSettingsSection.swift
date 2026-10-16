import SwiftUI

/// States whether the user's data is actually leaving the device, and lets the
/// user turn sync off or erase everything.
///
/// It sits directly above Backup on purpose: every state that means "not
/// syncing" ends by pointing at Export Data, and a footer that says so reads
/// better immediately above the button it is talking about.
struct ICloudSettingsSection: View {
    @Environment(StoreHost.self) private var storeHost
    @Environment(SyncHealthMonitor.self) private var syncHealth
    @Environment(ProStore.self) private var proStore
    @Environment(ProUpgradePresenter.self) private var upgradePresenter

    @State private var showsResetConfirmation = false
    @State private var resetConfirmationText = ""

    var body: some View {
        let health = displayedHealth
        let lastSync = syncHealth.lastSuccessfulSync
        // Last Synced and the sync row are conditional, so the sheet's shape
        // follows which of them are shown.
        let lastSyncOffset = lastSync == nil ? 0 : 1
        let shownSyncRow = health != .notMirrored
        let count = 2 + lastSyncOffset + (shownSyncRow ? 1 : 0)
        Section {
            HoneyLedgerLabeledRow("Status") {
                Group {
                    if let statusText = health.statusText {
                        Label(statusText, systemImage: health.statusSymbol)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Image(systemName: health.statusSymbol)
                    }
                }
                .foregroundStyle(syncTint(for: health.severity))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(health.accessibilityStatus)
            }
            .ledgerSheetRow(position: .position(index: 0, count: count))
            if let lastSync {
                HoneyLedgerLabeledRow("Last Synced") {
                    Text(lastSync.formatted(.relative(presentation: .named)))
                        .foregroundStyle(Color.inkSoft)
                }
                .ledgerSheetRow(position: .position(index: 1, count: count))
            }
            // A build without the iCloud entitlement can't sync either way.
            if shownSyncRow {
                if proStore.isPro {
                    Toggle("Sync with iCloud", isOn: syncToggle)
                        .foregroundStyle(Color.ink)
                        .tint(Color.amber)
                        .ledgerSheetRow(position: .position(index: 1 + lastSyncOffset, count: count))
                } else {
                    Button {
                        upgradePresenter.present(reason: .sync)
                    } label: {
                        Text("Upgrade to Pro")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.amberText)
                    }
                    .ledgerSheetRow(position: .position(index: 1 + lastSyncOffset, count: count))
                }
            }
            Button(role: .destructive) {
                resetConfirmationText = ""
                showsResetConfirmation = true
            } label: {
                Text("Reset Everything…")
                    .foregroundStyle(Color.danger)
            }
            .ledgerSheetRow(position: .position(index: count - 1, count: count))
        } header: {
            HoneyLedgerSectionLabel("iCloud")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if let relaunchNotice = storeHost.relaunchNotice(isPro: proStore.isPro) {
                    Text("\(Image(systemName: "arrow.clockwise.circle.fill")) \(relaunchNotice)")
                        .font(.footnote)
                        .foregroundStyle(Color.warning)
                }
                if let syncFooter {
                    HoneyLedgerFooter(syncFooter)
                }
            }
        }
        .alert("Reset Everything?", isPresented: $showsResetConfirmation) {
            TextField(AppReset.confirmationWord, text: $resetConfirmationText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Erase", role: .destructive) {
                guard AppReset.isConfirmed(by: resetConfirmationText) else { return }
                tearDown { storeHost.requestReset() }
            }
            .disabled(!AppReset.isConfirmed(by: resetConfirmationText))
            Button("Cancel", role: .cancel) {}
        } message: {
            // About the store open now, not a choice waiting for a relaunch.
            Text(AppReset.confirmationMessage(localCause: storeHost.localCause))
        }
    }

    private var syncToggle: Binding<Bool> {
        Binding(
            get: { !storeHost.prefersOffline },
            set: { storeHost.prefersOffline = !$0 }
        )
    }

    private var displayedHealth: SyncHealth {
        syncHealth.health.displayed(isPro: proStore.isPro, prefersOffline: storeHost.prefersOffline)
    }

    private var syncFooter: String? {
        let health = displayedHealth
        guard health.showsSettingsFooter else { return nil }
        let footer = health.settingsFooter
        guard let fallback = syncHealth.unresolvedFallback else {
            return footer
        }
        let when = fallback.formatted(date: .abbreviated, time: .shortened)
        return footer
            + "\n\nSoapWiz could not reach iCloud on \(when). Anything changed since then may "
            + "still be only on this device — use Export Data below to keep your own copy."
    }

    /// Without this the teardown animates, which keeps the outgoing screens
    /// mounted — and re-evaluating — while the store changes underneath them.
    private func tearDown(_ request: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, request)
    }

    private func syncTint(for severity: SyncSeverity) -> Color {
        switch severity {
        case .good: .success
        case .info: .inkSoft
        case .actionable: .warning
        case .fault: .danger
        }
    }
}
