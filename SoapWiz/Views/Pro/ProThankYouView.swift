import SwiftUI

/// What the sheet shows once Pro is unlocked.
struct ProThankYouView: View {
    let syncOutcome: ProSyncOutcome
    let onDone: () -> Void
    let onGoToSettings: (() -> Void)?

    private static let readyRow = ProBenefit(
        symbol: "checkmark",
        title: "Ready now",
        detail: "Unlimited recipes, collections and reminders.",
        tint: .success
    )

    private var syncRow: ProBenefit {
        switch syncOutcome {
        case .startsOnRelaunch:
            ProBenefit(
                symbol: "icloud",
                title: "iCloud sync",
                detail: "Starts the next time you open SoapWiz. Close it from the app switcher "
                    + "and open it again to start now."
            )
        case .isOff:
            ProBenefit(
                symbol: "exclamationmark.triangle",
                title: "iCloud sync is off",
                detail: "Pro doesn’t turn it on for you. Switch on Sync with iCloud in Settings, "
                    + "then open SoapWiz again.",
                tint: .warning,
                titleColor: .warning
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HoneyLedgerDiamondRule()
            VStack(alignment: .leading, spacing: 12) {
                Text("Thank you")
                    .font(.largeTitle.weight(.semibold))
                    .fontDesign(.serif)
                    .foregroundStyle(Color.ink)
                    .accessibilityAddTraits(.isHeader)
                StatusStamp(word: "Unlocked", tone: .success, glyph: "checkmark", isInked: true)
                Text("SoapWiz Pro is yours, on this device and any other signed in to the same Apple Account.")
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSoft)
            }
            ProBenefitsList(benefits: [Self.readyRow, syncRow])
            VStack(spacing: 12) {
                Button("Done", action: onDone)
                    .buttonStyle(.honeyLedgerPrimary)
                if syncOutcome == .isOff, let onGoToSettings {
                    Button("Go to iCloud settings", action: onGoToSettings)
                        .foregroundStyle(Color.amberText)
                }
            }
        }
    }
}
