import SwiftUI
import SwiftData

struct IngredientFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \IngredientCategory.name) private var categories: [IngredientCategory]
    @Query(sort: \QuantityUnit.name) private var units: [QuantityUnit]

    @State private var model: IngredientFormViewModel
    let onSave: ((Ingredient) -> Void)?

    init(ingredient: Ingredient? = nil, onSave: ((Ingredient) -> Void)? = nil) {
        _model = State(initialValue: IngredientFormViewModel(ingredient: ingredient))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $model.name)
                    Picker("Category", selection: $model.selectedCategory) {
                        Text("None").tag(Optional<IngredientCategory>.none)
                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category))
                        }
                    }
                    Picker("Unit", selection: $model.selectedUnit) {
                        Text("None").tag(Optional<QuantityUnit>.none)
                        ForEach(units) { unit in
                            Text("\(unit.name) (\(unit.symbol))").tag(Optional(unit))
                        }
                    }
                }

                Section {
                    HStack {
                        TextField("Low Stock Threshold", text: $model.lowStockThreshold)
                            .keyboardType(.decimalPad)
                        if let symbol = model.selectedUnit?.symbol {
                            Text(symbol)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Alerts")
                } footer: {
                    Text("You'll see a warning when stock falls at or below this amount. Leave blank to disable.")
                }
            }
            .navigationTitle(model.isEditing ? "Edit Ingredient" : "New Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isEditing ? "Save" : "Add") {
                        if let newIngredient = model.save(context: modelContext) {
                            onSave?(newIngredient)
                        }
                        dismiss()
                    }
                    .disabled(!model.isValid)
                }
            }
        }
    }
}
