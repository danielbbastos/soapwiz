import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    /// Confirming an import tears this view down, so the confirmation and everything
    /// that follows it live on `ContentView`. This screen only stages the file.
    @Environment(RestoreCoordinator.self) private var restore
    @Environment(SyncHealthMonitor.self) private var syncHealth
    @Query private var categories: [IngredientCategory]
    @Query private var locations: [StorageLocation]
    @Query private var providers: [Provider]
    @Query private var collections: [RecipeCollection]
    @Query private var settingsRecords: [AppSettings]
    private var settings: AppSettings? { AppSettings.canonical(from: settingsRecords) }

    @State private var showNotificationDenied = false
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
                inventorySection
                recipesSection
                if let settings {
                    notificationsSection(settings)
                    pricingSection(settings)
                }
                recipeImportSection
                syncSection
                backupSection
            }
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
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle("Settings")
            .warmBackground()
        }
    }

    private func notificationsSection(_ settings: AppSettings) -> some View {
        Section {
            Toggle("Expiry Reminders", isOn: Bindable(settings).expiryNotificationsEnabled)
        } header: {
            Text("Notifications")
        } footer: {
            Text("Get notified 1 month and 1 week before ingredients expire.")
        }
        .listRowBackground(Color.cardBackground)
        .onChange(of: settings.expiryNotificationsEnabled) { _, enabled in
            Task {
                if enabled {
                    let granted = await NotificationService.requestAuthorization()
                    if !granted {
                        settings.expiryNotificationsEnabled = false
                        showNotificationDenied = true
                    } else {
                        await NotificationService.syncNotifications(modelContext: modelContext)
                    }
                } else {
                    await NotificationService.cancelAllExpiryNotifications()
                }
            }
        }
        .alert("Notifications Disabled", isPresented: $showNotificationDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("SoapWiz needs notification permission to send expiry reminders. "
                 + "You can enable it in Settings.")
        }
    }

    private var inventorySection: some View {
        Section("Inventory") {
            NavigationLink(destination: CategoryListView()) {
                LabeledContent("Categories", value: "\(categories.count)")
            }
            NavigationLink(destination: StorageLocationListView()) {
                LabeledContent("Storage Locations", value: "\(locations.count)")
            }
            NavigationLink(destination: ProviderListView()) {
                LabeledContent("Providers", value: "\(providers.count)")
            }
        }
        .listRowBackground(Color.cardBackground)
    }

    /// Collections sit apart from the inventory lookups above: they group
    /// recipes, and the two axes never meet — an ingredient's category also
    /// decides what it can be picked as, which a theme must never do.
    private var recipesSection: some View {
        Section("Recipes") {
            NavigationLink(destination: RecipeCollectionListView()) {
                LabeledContent("Collections", value: "\(collections.count)")
            }
        }
        .listRowBackground(Color.cardBackground)
    }

    private func pricingSection(_ settings: AppSettings) -> some View {
        Section("Pricing") {
            HStack {
                Text("RRP factor")
                InfoPopoverIcon(
                    title: "RRP Factor",
                    text: "A multiplier applied to the total ingredient cost of a product to "
                        + "estimate its recommended retail price (RRP — Recommended Retail Price)."
                        + "\n\nFor example, a factor of 4 means a product costing €2.50 to make "
                        + "would be priced at €10.00."
                )
                Spacer()
                NumericTextField(prompt: "4", value: Bindable(settings).pvpFactor, fractionLength: 0...2)
            }
            .listRowBackground(Color.cardBackground)
        }
    }

    /// States why recipe import is or isn't on offer.
    ///
    /// The entry point on the Recipes tab stays hidden when the model can't run
    /// — a button that fails on tap is worse than no button. But hiding it
    /// silently leaves "Apple Intelligence is switched off" indistinguishable
    /// from "this feature doesn't exist", so the reason lives here.
    private var recipeImportSection: some View {
        let availability = RecipeImportAvailability.current
        return Section {
            LabeledContent("Status") {
                Label(availability.statusText, systemImage: availability.statusSymbol)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(statusTint(for: availability))
            }
        } header: {
            Text("Recipe Import")
        } footer: {
            Text(availability.settingsFooter)
        }
        .listRowBackground(Color.cardBackground)
    }

    private func statusTint(for availability: RecipeImportAvailability) -> Color {
        if availability.isAvailable { return .green }
        return availability.isActionable ? .orange : .secondary
    }

    /// States whether the user's data is actually leaving the device.
    ///
    /// It sits directly above Backup on purpose: every state that means "not
    /// syncing" ends by pointing at Export Data, and a footer that says so reads
    /// better immediately above the button it is talking about.
    private var syncSection: some View {
        let health = syncHealth.health
        return Section {
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
        } header: {
            Text("iCloud")
        } footer: {
            Text(syncFooter)
        }
        .listRowBackground(Color.cardBackground)
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

    private func syncTint(for severity: SyncSeverity) -> Color {
        switch severity {
        case .good: .green
        case .info: .secondary
        case .actionable: .orange
        case .fault: .red
        }
    }

    private var backupSection: some View {
        Section {
            Button {
                dataTransfer.export(from: modelContext)
            } label: {
                Label("Export Data", systemImage: "square.and.arrow.up")
            }
            Button {
                dataTransfer.isImporterPresented = true
            } label: {
                Label("Import Data", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("Export saves all your ingredients, recipes, and history to a single file. "
                 + "Importing a file replaces everything currently in the app.")
        }
        .listRowBackground(Color.cardBackground)
    }
}
