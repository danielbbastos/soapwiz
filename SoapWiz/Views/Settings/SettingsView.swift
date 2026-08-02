import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    /// Confirming an import tears this view down, so the confirmation and everything
    /// that follows it live on `ContentView`. This screen only stages the file.
    @Environment(RestoreCoordinator.self) private var restore
    @Query private var categories: [IngredientCategory]
    @Query private var locations: [StorageLocation]
    @Query private var providers: [Provider]
    @Query private var settingsRecords: [AppSettings]
    private var settings: AppSettings? { AppSettings.canonical(from: settingsRecords) }

    @State private var showPvpInfo = false
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
                if let settings {
                    notificationsSection(settings)
                    pricingSection(settings)
                }
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

    private func pricingSection(_ settings: AppSettings) -> some View {
        Section("Pricing") {
            HStack {
                Text("RRP factor")
                Button {
                    showPvpInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Spacer()
                TextField("4", value: Bindable(settings).pvpFactor,
                      format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
            }
            .listRowBackground(Color.cardBackground)
        }
        .sheet(isPresented: $showPvpInfo) {
            VStack(alignment: .leading, spacing: 12) {
                Text("RRP Factor")
                    .font(.headline)
                Text("A multiplier applied to the total ingredient cost of a product to estimate "
                     + "its recommended retail price (RRP — Recommended Retail Price)."
                     + "\n\nFor example, a factor of 4 means a product costing €2.50 to make "
                     + "would be priced at €10.00.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .presentationDetents([.fraction(0.35)])
            .presentationDragIndicator(.visible)
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
