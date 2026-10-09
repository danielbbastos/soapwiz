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

    @State private var showsResetConfirmation = false
    @State private var resetConfirmationText = ""

    var body: some View {
        let health = syncHealth.health
        let lastSync = syncHealth.lastSuccessfulSync
        // Last Synced and the toggle are conditional, so the sheet's shape
        // follows which of them are shown.
        let lastSyncOffset = lastSync == nil ? 0 : 1
        let shownToggle = health != .notMirrored
        let count = 2 + lastSyncOffset + (shownToggle ? 1 : 0)
        Section {
            HoneyLedgerLabeledRow("Status") {
                Label(health.statusText, systemImage: health.statusSymbol)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(syncTint(for: health.severity))
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
            if shownToggle {
                Toggle("Sync with iCloud", isOn: syncToggle)
                    .foregroundStyle(Color.ink)
                    .tint(Color.amber)
                    .ledgerSheetRow(position: .position(index: 1 + lastSyncOffset, count: count))
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
                if storeHost.needsRelaunch {
                    Label(relaunchNotice, systemImage: "arrow.clockwise.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.warning)
                }
                HoneyLedgerFooter(syncFooter)
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
            Text(AppReset.confirmationMessage(syncIsOff: storeHost.isOffline))
        }
    }

    private var syncToggle: Binding<Bool> {
        Binding(
            get: { !storeHost.prefersOffline },
            set: { storeHost.prefersOffline = !$0 }
        )
    }

    /// The store is opened once per launch, so a change waits for the next one.
    private var relaunchNotice: String {
        let change = storeHost.prefersOffline ? "turn off iCloud sync" : "turn iCloud sync back on"
        return "Close SoapWiz from the app switcher and open it again to \(change)."
    }

    private var syncFooter: String {
        guard let fallback = syncHealth.unresolvedFallback else {
            return syncHealth.health.settingsFooter
        }
        let when = fallback.formatted(date: .abbreviated, time: .shortened)
        return syncHealth.health.settingsFooter
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
