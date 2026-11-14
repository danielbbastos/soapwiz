import SwiftUI
import UniformTypeIdentifiers

/// What Home shows while the user has no data: ways to bring their things in,
/// or to start from a tested recipe. It is one readable column, never the
/// wide grid.
struct HomeFirstRunView: View {
    static let maximumWidth: CGFloat = 560

    @Environment(AppNavigation.self) private var navigation
    @Environment(InventoryRows.self) private var inventoryRows
    @Environment(RestoreCoordinator.self) private var restore
    @FreeTierGateEnvironment private var freeTier

    @State private var dataTransfer = DataTransferViewModel()

    private var importError: Binding<Bool> {
        Binding(
            get: { dataTransfer.errorMessage != nil },
            set: { if !$0 { dataTransfer.errorMessage = nil } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HomeLayout.spacing) {
            VStack(alignment: .leading, spacing: 12) {
                HoneyLedgerNote("Your workshop is empty. Bring what you already have, or start from a tested recipe.")
                if inventoryRows.syncNotice == .firstSync {
                    syncLine
                        .transition(.opacity)
                }
            }
            HomeCard("Bring my stuff") {
                row(
                    "Import inventory",
                    subtitle: "From a spreadsheet or another app",
                    systemImage: "tablecells",
                    isLast: false,
                    action: navigation.openInventoryImport
                )
                HomeCardDivider()
                row(
                    "Paste a recipe",
                    subtitle: "From SoapCalc, Soapmaking Friend and others",
                    systemImage: "doc.text.viewfinder",
                    isLast: false,
                    action: navigation.openRecipeImport
                )
                HomeCardDivider()
                row(
                    "Restore a backup",
                    subtitle: "A SoapWiz backup file",
                    systemImage: "clock.arrow.circlepath",
                    isLast: true
                ) {
                    dataTransfer.isImporterPresented = true
                }
            }
            HomeCard("New to soap making") {
                row(
                    "Start from a recipe",
                    subtitle: "Four starter recipes to copy and make",
                    systemImage: "book.closed",
                    isLast: true,
                    action: navigation.openStarterRecipes
                )
            }
            HoneyLedgerFooter("Cards for curing, stock and what you can make take over this screen as soon as you add something.")
        }
        .frame(maxWidth: Self.maximumWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .animation(.default, value: inventoryRows.syncNotice)
        .fileImporter(
            isPresented: $dataTransfer.isImporterPresented,
            allowedContentTypes: [.json]
        ) { result in
            dataTransfer.handleImportSelection(
                result,
                into: restore,
                isPro: freeTier.gate.isUnlimited,
                onOverLimit: { freeTier.presentUpgrade(for: .backupLimit) }
            )
        }
        .alert("Something went wrong", isPresented: importError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dataTransfer.errorMessage ?? "")
        }
    }

    private var syncLine: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.amberText)
                .accessibilityHidden(true)
            Text("Checking iCloud for your data…")
                .font(.subheadline)
                .foregroundStyle(Color.inkSoft)
        }
        .accessibilityElement(children: .combine)
    }

    private func row(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        systemImage: String,
        isLast: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HomeFirstRunRow(title: title, subtitle: subtitle, systemImage: systemImage)
        }
        .buttonStyle(HomeRowButtonStyle(isLast: isLast))
    }
}

private struct HomeFirstRunRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.amberText)
                .frame(width: 36, height: 36)
                .background(Color.honey, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ink)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSoft)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.inkFaint)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
