import SwiftUI
import SwiftData

/// The form sections shared by the single-purchase form (`PurchaseFormView`) and
/// the bulk import flow (`BulkImportFlowView`). Owns no navigation or toolbar so
/// each caller can wrap it with its own chrome.
struct PurchaseFormFields: View {
    @Environment(\.currencyCode) private var currencyCode
    @Bindable var model: PurchaseFormViewModel

    @Query(sort: \Provider.name) private var providers: [Provider]
    @Query(sort: \StorageLocation.name) private var storageLocations: [StorageLocation]

    @State private var showingNewProvider = false
    @State private var showingNewLocation = false

    private var unit: String { model.ingredient.unit }

    private var showsPricePerUnit: Bool { model.quantity > 0 && model.totalPrice > 0 }

    /// Each section draws its rows as one ledger sheet, so a row needs to know
    /// where among the rows its section shows it sits.
    private func sheetRow<Content: View>(
        _ index: Int,
        of count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content().ledgerSheetRow(position: .position(index: index, count: count))
    }

    private func datePicker(_ title: String, selection: Binding<Date>) -> some View {
        DatePicker(title, selection: selection, displayedComponents: .date)
            .foregroundStyle(Color.ink)
            .tint(Color.amberText)
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .foregroundStyle(Color.ink)
            .tint(Color.amber)
    }

    var body: some View {
        purchaseSection
        identificationSection
        datesSection
        storageSection
    }

    private var purchaseSection: some View {
        Section {
            let count = showsPricePerUnit ? 5 : 4
            sheetRow(0, of: count) { providerMenu }
            sheetRow(1, of: count) { datePicker("Date of Purchase", selection: $model.dateOfPurchase) }
            sheetRow(2, of: count) {
                HoneyLedgerField(
                    "Quantity",
                    text: $model.quantityText.decimalOnly(),
                    prompt: 0.0.formatted(),
                    unit: unit,
                    keyboard: .decimalPad
                )
            }
            sheetRow(3, of: count) {
                HoneyLedgerField(
                    "Total Price",
                    text: $model.totalPriceText.decimalOnly(),
                    prompt: 0.0.formatted(.number.precision(.fractionLength(2))),
                    keyboard: .decimalPad
                )
            }
            if showsPricePerUnit {
                sheetRow(4, of: count) {
                    HoneyLedgerCalculatedRow(
                        title: "Price / \(unit.isEmpty ? String(localized: "unit") : unit)",
                        value: model.pricePerUnit.unitPriceFormatted(currencyCode: currencyCode)
                    )
                }
            }
        }
    }

    private var identificationSection: some View {
        Section {
            sheetRow(0, of: 2) {
                HoneyLedgerField("Badge / Lot Number", text: $model.badge, prompt: "Optional")
            }
            sheetRow(1, of: 2) {
                HoneyLedgerField("Journal Code", text: $model.journalCode, prompt: "Optional")
            }
        } header: {
            HoneyLedgerSectionLabel("Identification")
        }
    }

    private var datesSection: some View {
        Section {
            let openingIndex = model.hasExpiryDate ? 2 : 1
            let count = openingIndex + (model.hasOpeningDate ? 2 : 1)
            sheetRow(0, of: count) { toggle("Has Expiry Date", isOn: $model.hasExpiryDate) }
            if model.hasExpiryDate {
                sheetRow(1, of: count) { datePicker("Expiry Date", selection: $model.expiryDate) }
            }
            sheetRow(openingIndex, of: count) { toggle("Has Been Opened", isOn: $model.hasOpeningDate) }
            if model.hasOpeningDate {
                sheetRow(openingIndex + 1, of: count) { datePicker("Opening Date", selection: $model.openingDate) }
            }
        } header: {
            HoneyLedgerSectionLabel("Dates")
        }
    }

    private var storageSection: some View {
        Section {
            sheetRow(0, of: 1) { locationMenu }
        } header: {
            HoneyLedgerSectionLabel("Storage")
        }
    }

    private var providerMenu: some View {
        Menu {
            Button { model.selectedProvider = nil } label: {
                MenuSelectionLabel("None", isSelected: model.selectedProvider == nil)
            }
            Button { showingNewProvider = true } label: {
                Label("New Provider", systemImage: "plus")
            }
            Divider()
            ForEach(providers) { provider in
                Button { model.selectedProvider = provider } label: {
                    MenuSelectionLabel(provider.name, isSelected: model.selectedProvider === provider)
                }
            }
        } label: {
            PickerMenuRowLabel(
                title: "Provider",
                value: model.selectedProvider?.name ?? String(localized: "None"),
                isPlaceholder: model.selectedProvider == nil
            )
        }
        .tint(.primary)
        .sheet(isPresented: $showingNewProvider) {
            ProviderFormView { newProvider in
                model.selectedProvider = newProvider
            }
        }
    }

    private var locationMenu: some View {
        Menu {
            Button { model.selectedLocation = nil } label: {
                MenuSelectionLabel("None", isSelected: model.selectedLocation == nil)
            }
            Button { showingNewLocation = true } label: {
                Label("New Location", systemImage: "plus")
            }
            Divider()
            ForEach(storageLocations) { location in
                Button { model.selectedLocation = location } label: {
                    MenuSelectionLabel(location.name, isSelected: model.selectedLocation === location)
                }
            }
        } label: {
            PickerMenuRowLabel(
                title: "Location",
                value: model.selectedLocation?.name ?? String(localized: "None"),
                isPlaceholder: model.selectedLocation == nil
            )
        }
        .tint(.primary)
        .sheet(isPresented: $showingNewLocation) {
            StorageLocationFormView { newLocation in
                model.selectedLocation = newLocation
            }
        }
    }
}
