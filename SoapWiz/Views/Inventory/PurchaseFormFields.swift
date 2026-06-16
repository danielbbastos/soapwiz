import SwiftUI
import SwiftData

/// The form sections shared by the single-purchase form (`PurchaseFormView`) and
/// the bulk import flow (`BulkImportFlowView`). Owns no navigation or toolbar so
/// each caller can wrap it with its own chrome.
struct PurchaseFormFields: View {
    @Bindable var model: PurchaseFormViewModel

    @Query(sort: \Provider.name) private var providers: [Provider]
    @Query(sort: \StorageLocation.name) private var storageLocations: [StorageLocation]

    @State private var showingNewProvider = false
    @State private var showingNewLocation = false

    var body: some View {
        Section("Purchase") {
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
                PickerMenuRowLabel(title: "Provider", value: model.selectedProvider?.name ?? "None")
            }
            .tint(.primary)
            .sheet(isPresented: $showingNewProvider) {
                ProviderFormView { newProvider in
                    model.selectedProvider = newProvider
                }
            }
            DatePicker("Date of Purchase", selection: $model.dateOfPurchase, displayedComponents: .date)
            HStack {
                Text("Quantity\(model.ingredient.unit.isEmpty ? "" : " (\(model.ingredient.unit))")")
                Spacer()
                TextField("0", text: $model.quantityText.decimalOnly())
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }
            HStack {
                Text("Total Price")
                Spacer()
                TextField("0.00", text: $model.totalPriceText.decimalOnly())
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }
            if model.quantity > 0 && model.totalPrice > 0 {
                LabeledContent("Price\(model.ingredient.unit.isEmpty ? "" : " / \(model.ingredient.unit)")") {
                    Text(model.pricePerUnit.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listRowBackground(Color.cardBackground)

        Section("Identification") {
            TextField("Badge / Lot Number", text: $model.badge)
            TextField("Journal Code", text: $model.journalCode)
        }
        .listRowBackground(Color.cardBackground)

        Section("Dates") {
            Toggle("Has Expiry Date", isOn: $model.hasExpiryDate)
            if model.hasExpiryDate {
                DatePicker("Expiry Date", selection: $model.expiryDate, displayedComponents: .date)
            }
            Toggle("Has Opening Date", isOn: $model.hasOpeningDate)
            if model.hasOpeningDate {
                DatePicker("Opening Date", selection: $model.openingDate, displayedComponents: .date)
            }
        }
        .listRowBackground(Color.cardBackground)

        Section("Storage") {
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
                PickerMenuRowLabel(title: "Location", value: model.selectedLocation?.name ?? "None")
            }
            .tint(.primary)
            .sheet(isPresented: $showingNewLocation) {
                StorageLocationFormView { newLocation in
                    model.selectedLocation = newLocation
                }
            }
        }
        .listRowBackground(Color.cardBackground)
    }
}
