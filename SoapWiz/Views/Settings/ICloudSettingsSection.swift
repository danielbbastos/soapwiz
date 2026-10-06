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
        Section {
            LabeledContent("Status") {
                Label(health.statusText, systemImage: health.statusSymbol)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(syncTint(for: health.severity))
            }
            if let lastSync = syncHealth.lastSuccessfulSync {
                LabeledContent(
                    "Last Synced",
                    value: lastSync.formatted(.relative(presentation: .named))
                )
            }
            // A build without the iCloud entitlement can't sync either way.
            if health != .notMirrored {
                Toggle("Sync with iCloud", isOn: syncToggle)
            }
            Button("Reset Everything…", role: .destructive) {
                resetConfirmationText = ""
                showsResetConfirmation = true
            }
        } header: {
            Text("iCloud")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if storeHost.needsRelaunch {
                    Label(relaunchNotice, systemImage: "arrow.clockwise.circle.fill")
                        .foregroundStyle(.orange)
                }
                Text(syncFooter)
            }
        }
        .listRowBackground(Color.cardBackground)
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
            Text(resetMessage)
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

    /// About the store open now, not the choice waiting for a relaunch.
    private var resetMessage: String {
        let scope = storeHost.isOffline
            ? "iCloud sync is off, so this erases this device only."
            : "This erases everything on this device and in iCloud, including your other devices."
        return "\(scope) Your ingredients, purchases, recipes and history are deleted, and "
            + "settings go back to their defaults. This can’t be undone. "
            + "Type \(AppReset.confirmationWord) to confirm."
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
        case .good: .green
        case .info: .secondary
        case .actionable: .orange
        case .fault: .red
        }
    }
}
