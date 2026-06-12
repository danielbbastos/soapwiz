import SwiftUI
import SwiftData

/// The form sections shared by the single-purchase form (`PurchaseFormView`) and
/// the bulk import flow (`BulkImportFlowView`). Owns no navigation or toolbar so
/// each caller can wrap it with its own chrome.
struct PurchaseFormFields: View {
    @Bindable var model: PurchaseFormViewModel

    @Query(sort: \Provider.name) private var providers: [Provider]
    @Query(sort: \StorageLocation.name) private var storageLocations: [StorageLocation]

    var body: some View {
        Section("Purchase") {
            Picker("Provider", selection: $model.selectedProvider) {
                Text("None").tag(Optional<Provider>.none)
                ForEach(providers) { provider in
                    Text(provider.name).tag(Optional(provider))
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
            Picker("Location", selection: $model.selectedLocation) {
                Text("None").tag(Optional<StorageLocation>.none)
                ForEach(storageLocations) { location in
                    Text(location.name).tag(Optional(location))
                }
            }
        }
        .listRowBackground(Color.cardBackground)
    }
}
