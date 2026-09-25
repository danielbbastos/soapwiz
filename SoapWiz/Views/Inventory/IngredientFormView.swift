import SwiftUI
import SwiftData

struct IngredientFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \IngredientCategory.name) private var categories: [IngredientCategory]
    @Query private var allIngredients: [Ingredient]

    @State private var model: IngredientFormViewModel
    @State private var showingNewCategory = false
    @State private var showingChemistryConfirmation = false
    @State private var profileExpanded = false
    let onSave: ((Ingredient) -> Void)?

    init(
        ingredient: Ingredient? = nil,
        defaultCategory: IngredientCategory? = nil,
        prefilledName: String? = nil,
        onSave: ((Ingredient) -> Void)? = nil
    ) {
        _model = State(initialValue: IngredientFormViewModel(
            ingredient: ingredient,
            defaultCategory: defaultCategory,
            prefilledName: prefilledName
        ))
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
                    PhotoField(imageData: $model.imageData) {
                        IngredientAvatar(
                            letter: model.avatarLetter,
                            color: model.avatarColor,
                            side: PhotoFieldWell.side
                        )
                    }
                    TextField("Name", text: $model.name)
                        .onChange(of: model.name) { _, _ in
                            model.applyNameChange(existingCodes: existingCodes)
                        }
                    codeField
                    Menu {
                        Button { model.selectedCategory = nil } label: {
                            MenuSelectionLabel("None", isSelected: model.selectedCategory == nil)
                        }
                        Button { showingNewCategory = true } label: {
                            Label("New Category", systemImage: "plus")
                        }
                        Divider()
                        ForEach(categories) { category in
                            Button { model.selectedCategory = category } label: {
                                MenuSelectionLabel(category.name, isSelected: model.selectedCategory === category)
                            }
                        }
                    } label: {
                        PickerMenuRowLabel(title: "Category", value: model.selectedCategory?.name ?? "None")
                    }
                    .tint(.primary)
                    Picker("Unit", selection: $model.selectedUnit) {
                        Text("None").tag(Optional<IngredientUnit>.none)
                        ForEach(IngredientUnit.allCases, id: \.self) { unit in
                            Text("\(unit.label) (\(unit.rawValue))").tag(Optional(unit))
                        }
                    }
                }
                .listRowBackground(Color.cardBackground)

                if model.showsSapValue || model.showsDensity {
                    Section("Properties") {
                        if model.showsSapValue {
                            decimalRow(title: "SAP Value (NaOH)", placeholder: 0.134, text: $model.sapValue, unit: "g/g")
                            decimalRow(title: "SAP Value (KOH)", placeholder: 0.188, text: $model.kohSapValue, unit: "g/g")
                        }
                        if model.showsDensity {
                            decimalRow(title: "Density", placeholder: 0.92, text: $model.density, unit: "g/ml")
                        }
                    }
                    .listRowBackground(Color.cardBackground)
                }

                if model.showsSapValue {
                    Section {
                        if profileExpanded {
                            FattyAcidProfileEditor(profile: $model.fattyAcidProfile)
                        }
                    } header: {
                        CollapsibleSectionHeader(title: "Fatty-Acid Profile", expanded: $profileExpanded)
                    } footer: {
                        if profileExpanded {
                            Text("Used to work out an oil's soap qualities — hardness, cleansing, "
                                 + "conditioning and the rest. Leave blank if you don't have it.")
                        }
                    }
                    .listRowBackground(Color.cardBackground)
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
                .listRowBackground(Color.cardBackground)
            }
            .navigationTitle(model.isEditing ? "Edit Ingredient" : "New Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle(model.isEditing ? "Edit Ingredient" : "New Ingredient")
            .warmBackground()
            // A prefilled name arrives before the field exists, so the
            // `onChange` that derives the code never fires for it.
            .task {
                if !model.isEditing, !model.name.isEmpty, model.code.isEmpty {
                    model.applyNameChange(existingCodes: existingCodes)
                }
                model.captureSnapshot()
            }
            .interactiveDismissDisabled(model.isDirty)
            .alert("Make This a Custom Ingredient?", isPresented: $showingChemistryConfirmation) {
                Button("Save as Custom") { commit() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("\"\(model.trimmedName)\" comes from the built-in ingredient library. "
                     + "Saving different chemistry makes it your own, marked Custom in its details.")
            }
            .sheet(isPresented: $showingNewCategory) {
                CategoryFormView { newCategory in
                    model.selectedCategory = newCategory
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isEditing ? "Save" : "Add") {
                        if model.changesLibraryChemistry {
                            showingChemistryConfirmation = true
                        } else {
                            commit()
                        }
                    }
                    .disabled(!model.isValid || model.codeHasDuplicate(among: allIngredients))
                }
            }
        }
    }

    /// The save itself, split out because two paths reach it: a straight Save, and
    /// the one that first asks about turning a library ingredient custom.
    private func commit() {
        if let newIngredient = model.save(context: modelContext) {
            onSave?(newIngredient)
        }
        dismiss()
    }

    private var codeBinding: Binding<String> {
        Binding(
            get: { model.code },
            set: { model.code = $0; model.markCodeEdited() }
        )
    }

    /// One trailing-aligned decimal field with a trailing unit label. The SAP and
    /// density rows are the same shape, so they share this rather than repeating it.
    private func decimalRow(title: String, placeholder: Double, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(placeholder.formatted(), text: text.decimalOnly())
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit)
                .foregroundStyle(.secondary)
        }
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
