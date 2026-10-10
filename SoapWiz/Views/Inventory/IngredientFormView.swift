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
                Section {
                    PhotoField(imageData: $model.imageData) {
                        IngredientAvatar(
                            letter: model.avatarLetter,
                            color: model.avatarColor,
                            side: PhotoFieldWell.side
                        )
                    }
                    .ledgerSheetRow(position: .first)
                    HoneyLedgerField("Name", text: $model.name, prompt: "Required")
                        .onChange(of: model.name) { _, _ in
                            model.applyNameChange(existingCodes: existingCodes)
                        }
                        .ledgerSheetRow(position: .middle)
                    HoneyLedgerField(
                        "Ingredient Code",
                        text: codeBinding,
                        prompt: "Optional",
                        error: model.codeProblem(among: allIngredients)?.message
                    )
                    .textInputAutocapitalization(.characters)
                    .ledgerSheetRow(position: .middle)
                    categoryMenu
                        .ledgerSheetRow(position: .middle)
                    unitMenu
                        .ledgerSheetRow(position: .last)
                } header: {
                    HoneyLedgerSectionLabel("Details")
                }

                if model.showsSapValue || model.showsDensity {
                    Section {
                        let count = (model.showsSapValue ? 2 : 0) + (model.showsDensity ? 1 : 0)
                        if model.showsSapValue {
                            decimalField("SAP Value (NaOH)", placeholder: 0.134, text: $model.sapValue, unit: "g/g")
                                .ledgerSheetRow(position: .position(index: 0, count: count))
                            decimalField("SAP Value (KOH)", placeholder: 0.188, text: $model.kohSapValue, unit: "g/g")
                                .ledgerSheetRow(position: .position(index: 1, count: count))
                        }
                        if model.showsDensity {
                            decimalField("Density", placeholder: 0.92, text: $model.density, unit: "g/ml")
                                .ledgerSheetRow(position: .position(index: count - 1, count: count))
                        }
                    } header: {
                        HoneyLedgerSectionLabel("Properties")
                    }
                }

                if model.showsSapValue {
                    Section {
                        if profileExpanded {
                            FattyAcidProfileEditor(profile: $model.fattyAcidProfile)
                        }
                    } header: {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { profileExpanded.toggle() }
                        } label: {
                            HoneyLedgerSectionLabel("Fatty-Acid Profile", isExpanded: profileExpanded)
                        }
                        .buttonStyle(.plain)
                    } footer: {
                        if profileExpanded {
                            HoneyLedgerFooter("Used to work out an oil's soap qualities — hardness, cleansing, "
                                   + "conditioning and the rest. Leave blank if you don't have it.")
                        }
                    }
                }

                Section {
                    decimalField(
                        "Low Stock Threshold",
                        placeholder: nil,
                        text: $model.lowStockThreshold,
                        // Not after the "None" placeholder: "None g" reads as an amount.
                        unit: model.lowStockThreshold.isEmpty ? nil : model.selectedUnit?.rawValue
                    )
                    .ledgerSheetRow(position: .only)
                } header: {
                    HoneyLedgerSectionLabel("Alerts")
                } footer: {
                    HoneyLedgerFooter("You'll see a warning when stock falls at or below this amount. Leave blank to disable.")
                }
            }
            .environment(\.defaultMinListRowHeight, 48)
            .navigationTitle(model.isEditing ? "Edit Ingredient" : "New Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle(model.isEditing ? "Edit Ingredient" : "New Ingredient")
            .ledgerBackground()
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

    /// A decimal field with its unit. The SAP, density and threshold rows are the
    /// same shape, so they share this rather than repeating it. A nil
    /// `placeholder` reads "None", for a field left blank to switch it off.
    private func decimalField(
        _ title: String,
        placeholder: Double?,
        text: Binding<String>,
        unit: String?
    ) -> some View {
        HoneyLedgerField(
            title,
            text: text.decimalOnly(),
            prompt: placeholder?.formatted() ?? String(localized: "None"),
            unit: unit,
            keyboard: .decimalPad
        )
    }

    private var categoryMenu: some View {
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
            PickerMenuRowLabel(
                title: "Category",
                value: model.selectedCategory?.name ?? String(localized: "None"),
                isPlaceholder: model.selectedCategory == nil
            )
        }
        .tint(.primary)
    }

    /// A menu rather than a `Picker`: a menu picker draws its value in the
    /// accent colour, and amber is only ever a fill.
    private var unitMenu: some View {
        Menu {
            Button { model.selectedUnit = nil } label: {
                MenuSelectionLabel("None", isSelected: model.selectedUnit == nil)
            }
            Divider()
            let units = IngredientUnit.allCases
            let symbols = MenuColumnPadding.padded(units.map(\.rawValue))
            ForEach(Array(zip(units, symbols)), id: \.0) { unit, symbol in
                Button { model.selectedUnit = unit } label: {
                    MenuSelectionLabel("\(symbol) · \(unit.label)", isSelected: model.selectedUnit == unit)
                }
            }
        } label: {
            PickerMenuRowLabel(
                title: "Unit",
                value: model.selectedUnit.map(unitName) ?? String(localized: "None"),
                isPlaceholder: model.selectedUnit == nil
            )
        }
        .tint(.primary)
    }

    private func unitName(_ unit: IngredientUnit) -> String {
        "\(unit.rawValue) · \(unit.label)"
    }
}
