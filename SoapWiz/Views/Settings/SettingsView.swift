import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    /// Confirming an import tears this view down, so the confirmation and everything
    /// that follows it live on `ContentView`. This screen only stages the file.
    @Environment(RestoreCoordinator.self) private var restore
    @Environment(\.currencyCode) private var currencyCode
    @Environment(\.isTourSandbox) private var isTourSandbox
    @Environment(TourLauncher.self) private var tourLauncher
    @Environment(\.scenePhase) private var scenePhase
    @FreeTierGateEnvironment private var freeTier
    @Query private var categories: [IngredientCategory]
    @Query private var locations: [StorageLocation]
    @Query private var providers: [Provider]
    @Query private var collections: [RecipeCollection]
    @Query private var settingsRecords: [AppSettings]
    private var settings: AppSettings? { AppSettings.canonical(from: settingsRecords) }

    @State private var showNotificationDenied = false
    /// This device's notification permission, read when the screen appears and
    /// whenever the app comes back to the foreground, which is how the user
    /// returns after changing it in iOS Settings.
    @State private var notificationAuthorization: UNAuthorizationStatus?
    @State private var dataTransfer = DataTransferViewModel()

    private var importError: Binding<Bool> {
        Binding(
            get: { dataTransfer.errorMessage != nil },
            set: { if !$0 { dataTransfer.errorMessage = nil } }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if !isTourSandbox {
                    ProSettingsSection()
                }
                if let settings {
                    stockTrackingSection(settings)
                }
                inventorySection
                recipesSection
                if let settings {
                    // Expiry reminders are about recorded stock, so they go with it.
                    // Not in the tour: reminders would reach the real notification center.
                    if settings.tracksInventory, !isTourSandbox {
                        notificationsSection(settings)
                    }
                    pricingSection(settings)
                }
                // Not in the tour: import, iCloud, restore and reset all act on the real app.
                if !isTourSandbox {
                    recipeImportSection
                    ICloudSettingsSection()
                    backupSection
                }
                aboutSection
            }
            .readableWidth()
            .sheet(item: $dataTransfer.exportFile) { file in
                ShareSheet(items: [file.url])
            }
            .fileImporter(
                isPresented: $dataTransfer.isImporterPresented,
                allowedContentTypes: [.json]
            ) { result in
                dataTransfer.handleImportSelection(result, into: restore)
            }
            .alert("Something went wrong", isPresented: importError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(dataTransfer.errorMessage ?? "")
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .ledgerLargeTitle()
            .ledgerBackground()
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await refreshNotificationAuthorization()
            }
        }
    }

    private func refreshNotificationAuthorization() async {
        notificationAuthorization = await NotificationService.authorizationStatus()
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func notificationsSection(_ settings: AppSettings) -> some View {
        let includesReminders = freeTier.gate.allows(.reminders)
        let mayNotNotify = notificationAuthorization.map {
            NotificationService.deviceMayNotNotify(for: settings, authorization: $0, isPro: includesReminders)
        } ?? false
        return Section {
            reminderRow(
                "Expiry Reminders",
                subtitle: "1 month and 1 week before an ingredient expires",
                isOn: reminderToggle(\.expiryNotificationsEnabled, of: settings)
            )
            .ledgerSheetRow(position: .first)
            reminderRow(
                "Cure Reminders",
                subtitle: "The mornings a batch becomes usable and finishes curing",
                isOn: reminderToggle(\.cureNotificationsEnabled, of: settings)
            )
            .ledgerSheetRow(position: .last)
        } header: {
            HStack(spacing: 8) {
                HoneyLedgerSectionLabel("Notifications")
                if !includesReminders {
                    ProBadge()
                }
            }
        } footer: {
            notificationsFooter(includesReminders: includesReminders, mayNotNotify: mayNotNotify)
        }
        // However the setting changed, from a tap, another device or a restore,
        // this device schedules, cancels or skips its own reminders to match,
        // and never writes the setting back.
        .onChange(of: settings.expiryNotificationsEnabled) {
            syncReminders()
        }
        .onChange(of: settings.cureNotificationsEnabled) {
            syncReminders()
        }
        .alert("Notifications Disabled", isPresented: $showNotificationDenied) {
            Button("Open Settings", action: openAppSettings)
            Button("OK", role: .cancel) {}
        } message: {
            Text("SoapWiz needs notification permission to send reminders. "
                 + "You can enable it in Settings.")
        }
    }

    @ViewBuilder
    private func notificationsFooter(includesReminders: Bool, mayNotNotify: Bool) -> some View {
        if !includesReminders {
            HoneyLedgerFooter("Reminders are part of SoapWiz Pro. Your choices are kept for when you upgrade.")
        } else if mayNotNotify {
            // The setting is shared across devices and the permission isn't,
            // so this one can show reminders on while none arrive here.
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "Notifications are turned off for SoapWiz on this device, "
                        + "so reminders won't arrive here.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(Color.warning)
                Button("Open Settings", action: openAppSettings)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.amberText)
            }
        }
    }

    private func reminderRow(_ title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Color.ink)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.inkSoft)
            }
        }
        .tint(Color.amber)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .foregroundStyle(Color.ink)
            .tint(Color.amber)
    }

    private func countRow(_ title: String, count: Int, showsProBadge: Bool = false) -> some View {
        HoneyLedgerLabeledRow(title) {
            HStack(spacing: 8) {
                if showsProBadge {
                    ProBadge()
                }
                Text("\(count)")
                    .foregroundStyle(Color.inkSoft)
                    .monospacedDigit()
            }
        }
    }

    private func linkLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            Text(title)
                .foregroundStyle(Color.ink)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Color.inkSoft)
        }
    }

    /// A binding of its own rather than the stored value, so the permission
    /// request runs for a tap and only for a tap; see `applyToggle`.
    private func reminderToggle(
        _ setting: ReferenceWritableKeyPath<AppSettings, Bool>,
        of settings: AppSettings
    ) -> Binding<Bool> {
        Binding(
            get: { freeTier.gate.allows(.reminders) && settings[keyPath: setting] },
            set: { newValue in
                freeTier.ifAvailable(.reminders) {
                    Task {
                        showNotificationDenied = await NotificationService.applyToggle(newValue, setting: setting) {
                            AppSettings.resolve(in: modelContext)
                        }
                        await refreshNotificationAuthorization()
                    }
                }
            }
        )
    }

    private func syncReminders() {
        Task {
            await NotificationService.syncIfEnabled(modelContext: modelContext)
            await refreshNotificationAuthorization()
        }
    }

    /// A section of its own so the footer explaining the toggle sits directly
    /// under it, rather than under the Inventory lookups.
    private func stockTrackingSection(_ settings: AppSettings) -> some View {
        Section {
            toggleRow("Track ingredient stock", isOn: Bindable(settings).tracksInventory)
                .onChange(of: settings.tracksInventory) { _, tracks in
                    // `SettingsState` reads the settings when the context saves,
                    // so the other tabs follow the toggle at once.
                    modelContext.saveLoggingFailure()
                    // Cancelling takes no context, so it would clear the user's
                    // real expiry reminders from inside the tour.
                    guard !isTourSandbox else { return }
                    Task {
                        if tracks {
                            await NotificationService.syncIfEnabled(modelContext: modelContext)
                        } else {
                            await NotificationService.cancelAllExpiryNotifications()
                        }
                    }
                }
                .ledgerSheetRow(position: .only)
        } header: {
            // The Pro section carries the ornament; it is hidden in the tour.
            if isTourSandbox {
                // The List's first-header inset leaves the ornament lower than
                // centred; it clamps this negative padding to about 7pt up.
                HoneyLedgerOrnament()
                    .padding(.top, -10)
            }
        } footer: {
            HoneyLedgerFooter(
                "Turn off to use SoapWiz without recording purchases: batches don't check "
                    + "or deduct stock, stock and expiry warnings are hidden, and costs aren't shown. "
                    + "Your purchases are kept for when you turn it back on."
            )
        }
    }

    private var inventorySection: some View {
        Section {
            NavigationLink(destination: CategoryListView()) {
                countRow("Categories", count: categories.count)
            }
            .ledgerSheetRow(position: .first, navigates: true)
            NavigationLink(destination: StorageLocationListView()) {
                countRow("Storage Locations", count: locations.count)
            }
            .ledgerSheetRow(position: .middle, navigates: true)
            NavigationLink(destination: ProviderListView()) {
                countRow("Providers", count: providers.count)
            }
            .ledgerSheetRow(position: .last, navigates: true)
        } header: {
            HoneyLedgerSectionLabel("Inventory")
        }
    }

    /// Collections sit apart from the inventory lookups above: they group
    /// recipes, and the two axes never meet — an ingredient's category also
    /// decides what it can be picked as, which a theme must never do.
    private var recipesSection: some View {
        Section {
            NavigationLink(destination: RecipeCollectionListView()) {
                countRow("Collections", count: collections.count, showsProBadge: !freeTier.gate.allows(.collections))
            }
            .ledgerSheetRow(position: .only, navigates: true)
        } header: {
            HoneyLedgerSectionLabel("Recipes")
        }
    }

    private func pricingSection(_ settings: AppSettings) -> some View {
        Section {
            CurrencyPickerRow(settings: settings)
                .ledgerSheetRow(position: .first, navigates: true)
            HStack {
                Text("RRP factor")
                    .foregroundStyle(Color.ink)
                    .layoutPriority(1)
                InfoPopoverIcon(
                    title: "RRP Factor",
                    text: "A multiplier applied to the total ingredient cost of a product to "
                        + "estimate its recommended retail price (RRP — Recommended Retail Price)."
                        + "\n\nFor example, a factor of 4 means a product costing "
                        + "\(2.5.formatted(.currency(code: currencyCode))) to make "
                        + "would be priced at \(10.0.formatted(.currency(code: currencyCode)))."
                )
                NumericTextField(
                    prompt: "4", value: Bindable(settings).pvpFactor, fractionLength: 0...2, fillsAvailableWidth: true
                )
            }
            .ledgerSheetRow(position: .last)
        } header: {
            HoneyLedgerSectionLabel("Pricing")
        } footer: {
            HoneyLedgerFooter("Prices are kept as amounts, so changing the currency relabels them without converting.")
        }
    }

    private var aboutSection: some View {
        Section {
            HoneyLedgerLabeledRow("Version") {
                Text(Bundle.main.appVersionDisplay)
                    .foregroundStyle(Color.inkSoft)
            }
            .ledgerSheetRow(position: .first)
            // Not in the tour: replaying it from inside itself would nest covers.
            if !isTourSandbox {
                Button {
                    tourLauncher.replay()
                } label: {
                    linkLabel("Show Tour", systemImage: "sparkles")
                }
                .ledgerSheetRow(position: .middle)
            }
            NavigationLink(destination: LyeSafetyScreen()) {
                linkLabel("Lye Safety", systemImage: "exclamationmark.triangle")
            }
            .ledgerSheetRow(position: .middle, navigates: true)
            Link(destination: AppLinks.privacyPolicy) {
                linkLabel("Privacy Policy", systemImage: "hand.raised")
            }
            .ledgerSheetRow(position: .middle)
            Link(destination: AppLinks.support) {
                linkLabel("Support", systemImage: "questionmark.circle")
            }
            .ledgerSheetRow(position: .last)
        } header: {
            HoneyLedgerSectionLabel("About")
        }
    }

    private var backupSection: some View {
        Section {
            toggleRow("Include Photos", isOn: $dataTransfer.includesPhotos)
                .ledgerSheetRow(position: .first)
            HoneyLedgerActionRow("Export Data", systemImage: "square.and.arrow.up") {
                dataTransfer.export(from: modelContext)
            }
            .ledgerSheetRow(position: .middle)
            HoneyLedgerActionRow("Import Data", systemImage: "square.and.arrow.down") {
                dataTransfer.isImporterPresented = true
            }
            .ledgerSheetRow(position: .last)
        } header: {
            HoneyLedgerSectionLabel("Backup")
        } footer: {
            HoneyLedgerFooter(
                "Export saves all your ingredients, recipes, and history to a single file. "
                    + "Leaving photos out makes a much smaller file, but importing it brings "
                    + "everything back without them. "
                    + "Importing a file replaces everything currently in the app."
            )
        }
    }
}
