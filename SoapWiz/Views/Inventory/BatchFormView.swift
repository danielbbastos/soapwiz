import SwiftUI
import SwiftData

struct BatchFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Provider.name) private var providers: [Provider]
    @Query(sort: \StorageLocation.name) private var storageLocations: [StorageLocation]

    @State private var model: BatchFormViewModel

    init(ingredient: Ingredient, batch: IngredientBatch? = nil) {
        _model = State(initialValue: BatchFormViewModel(ingredient: ingredient, batch: batch))
    }

    var body: some View {
        NavigationStack {
            Form {
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

                Section("Identification") {
                    TextField("Badge / Lot Number", text: $model.badge)
                    TextField("Journal Code", text: $model.journalCode)
                }

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

                Section("Storage") {
                    Picker("Location", selection: $model.selectedLocation) {
                        Text("None").tag(Optional<StorageLocation>.none)
                        ForEach(storageLocations) { location in
                            Text(location.name).tag(Optional(location))
                        }
                    }
                }
            }
            .navigationTitle(model.isEditing ? "Edit Batch" : "New Batch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isEditing ? "Save" : "Add") {
                        model.save(context: modelContext)
                        dismiss()
                    }
                    .disabled(!model.isValid)
                }
            }
        }
    }
}
