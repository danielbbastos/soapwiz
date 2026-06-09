import SwiftUI
import SwiftData

struct IngredientFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \IngredientCategory.name) private var categories: [IngredientCategory]
    @Query private var allIngredients: [Ingredient]

    @State private var model: IngredientFormViewModel
    let onSave: ((Ingredient) -> Void)?

    init(ingredient: Ingredient? = nil, onSave: ((Ingredient) -> Void)? = nil) {
        _model = State(initialValue: IngredientFormViewModel(ingredient: ingredient))
        self.onSave = onSave
    }

    private var existingCodes: [String] {
        allIngredients.compactMap {
            guard $0 !== model.ingredient, !$0.code.isEmpty else { return nil }
            return $0.code
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $model.name)
                        .onChange(of: model.name) { _, _ in
                            model.applyNameChange(existingCodes: existingCodes)
                        }
                    codeField
                    Picker("Category", selection: $model.selectedCategory) {
                        Text("None").tag(Optional<IngredientCategory>.none)
                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category))
                        }
                    }
                    Picker("Unit", selection: $model.selectedUnit) {
                        Text("None").tag(Optional<IngredientUnit>.none)
                        ForEach(IngredientUnit.allCases, id: \.self) { unit in
                            Text("\(unit.label) (\(unit.rawValue))").tag(Optional(unit))
                        }
                    }
                }

                if model.showsSapValue || model.showsDensity {
                    Section("Properties") {
                        if model.showsSapValue {
                            HStack {
                                Text("SAP Value (NaOH)")
                                Spacer()
                                TextField("0.134", text: $model.sapValue.decimalOnly())
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                Text("g/g")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if model.showsDensity {
                            HStack {
                                Text("Density")
                                Spacer()
                                TextField("0.92", text: $model.density.decimalOnly())
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                Text("g/ml")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        TextField("Low Stock Threshold", text: $model.lowStockThreshold.decimalOnly())
                            .keyboardType(.decimalPad)
                        if let symbol = model.selectedUnit?.rawValue {
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
                    .disabled(!model.isValid || model.codeHasDuplicate(among: allIngredients))
                }
            }
        }
    }

    private var codeBinding: Binding<String> {
        Binding(
            get: { model.code },
            set: { model.code = $0; model.markCodeEdited() }
        )
    }

    @ViewBuilder
    private var codeField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Ingredient Code", text: codeBinding)
                .textInputAutocapitalization(.characters)
            if model.codeHasDuplicate(among: allIngredients) {
                Text("This code is already in use.")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if !model.trimmedCode.isEmpty && model.trimmedCode.count < 3 {
                Text("Code must be at least 3 characters.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
