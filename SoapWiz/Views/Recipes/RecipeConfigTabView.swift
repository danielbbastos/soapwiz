import SwiftUI
import SwiftData

private let weightUnits = ["g", "oz", "lb", "kg", "%"]
private let absoluteWeightUnits = ["g", "oz", "lb", "kg"]

/// The recipe form's Config tab: name, collections, what the recipe makes,
/// weight, lye and fragrance settings. Its own view rather than an extension on
/// `RecipeFormView`, matching the Ingredients and Stats tabs, so the state it
/// alone uses (the mold sheet, the new-collection sheet, the oil-weight focus)
/// lives with it instead of on the form.
struct RecipeConfigTabView: View {
    @Bindable var model: RecipeFormViewModel

    /// Additives the neutraliser switch may move its default to. Hidden rows are
    /// excluded, as the form's and detail's default queries exclude them, so a
    /// default never lands on an ingredient the user has said they don't use.
    private static let additivesPredicate: Predicate<Ingredient> = {
        let name = IngredientCategory.Name.additives
        return #Predicate { $0.category?.name == name && !$0.isHidden }
    }()

    @Query(sort: \RecipeCollection.name) private var collections: [RecipeCollection]
    @Query(filter: RecipeConfigTabView.additivesPredicate) private var additiveIngredients: [Ingredient]
    /// All ingredients, unfiltered — the cream-soap toggle resolves its glycerine
    /// against the same set the extras table matches, so an ingredient the user
    /// can see there is the one it auto-adds, whatever category it sits in.
    @Query(sort: \Ingredient.name) private var allIngredients: [Ingredient]

    @State private var showMoldCalculator = false
    @State private var showNewCollection = false
    @FocusState private var oilWeightFocused: Bool

    var body: some View {
        Form {
            detailsSection
            productKindSection
            weightSection
            if model.makesSoap {
                lyeSection
                soapMethodSection
            }
            fragranceSection
        }
        .readableWidth()
        .scrollClipDisabled()
        .animation(.default, value: model.makesSoap)
        .sheet(isPresented: $showMoldCalculator) {
            MoldCalculatorView(oilWeightUnit: model.oilWeightUnit) { weight in
                model.totalOilWeight = weight
            }
        }
        .sheet(isPresented: $showNewCollection) {
            RecipeCollectionFormView { newCollection in
                model.toggleCollection(newCollection)
            }
        }
    }

    private func sheetRow<Content: View>(
        _ index: Int,
        of count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content().ledgerSheetRow(position: .position(index: index, count: count))
    }

    private func footer(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.inkSoft)
    }

    private var detailsSection: some View {
        Section {
            sheetRow(0, of: 4) {
                HoneyLedgerField("Name", text: $model.name, prompt: "Required")
            }
            sheetRow(1, of: 4) {
                HoneyLedgerStackedField(
                    title: "Description",
                    text: $model.desc,
                    prompt: "What makes this recipe special"
                )
            }
            sheetRow(2, of: 4) { PhotoField(imageData: $model.imageData) }
            sheetRow(3, of: 4) { collectionsMenu }
        } header: {
            HoneyLedgerSectionLabel("Details")
        }
    }

    /// Multi-select, so the menu stays open-and-tap rather than a picker: a
    /// recipe belongs to several themes at once, which is the whole reason
    /// collections aren't folders.
    private var collectionsMenu: some View {
        Menu {
            Button { showNewCollection = true } label: {
                Label("New Collection", systemImage: "plus")
            }
            if !collections.isEmpty {
                Divider()
                ForEach(collections) { collection in
                    Button { model.toggleCollection(collection) } label: {
                        MenuSelectionLabel(collection.name, isSelected: model.isSelected(collection))
                    }
                }
            }
        } label: {
            PickerMenuRowLabel(title: "Collections", value: model.collectionsLabel)
        }
        .tint(.primary)
    }

    /// Hidden rather than disabled: a greyed-out superfat stepper on a candle
    /// recipe is noise. The lye fields keep their stored values while this is on,
    /// so switching back is lossless.
    private var productKindSection: some View {
        Section {
            toggleRow("Non-soap recipe", isOn: $model.isNonSoapProduct)
                .ledgerSheetRow(position: .only)
        } footer: {
            footer("Turn on for balms, lotions and other recipes without lye.")
        }
    }

    private var weightSection: some View {
        Section {
            let count = model.weightUnitIsPercentage ? 4 : 1
            sheetRow(0, of: count) {
                unitMenu("Unit", units: weightUnits, selection: $model.weightUnit)
            }
            if model.weightUnitIsPercentage {
                sheetRow(1, of: count) {
                    HoneyLedgerField(model.baseWeightLabel, unit: model.oilWeightUnit) { focus in
                        NumericTextField(prompt: "0", value: $model.totalOilWeight,
                                         width: 80, fillsAvailableWidth: true, focus: focus)
                            .focused($oilWeightFocused)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                sheetRow(2, of: count) {
                    unitMenu("Weight unit", units: absoluteWeightUnits, selection: $model.oilWeightUnit)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                sheetRow(3, of: count) {
                    Button {
                        showMoldCalculator = true
                    } label: {
                        Label("Calculate from mold…", systemImage: "ruler")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.amberText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } header: {
            HoneyLedgerSectionLabel(model.makesSoap ? "Oils" : "Weight")
        }
        .animation(.default, value: model.weightUnitIsPercentage)
        .onChange(of: model.weightUnitIsPercentage) { _, isPercentage in
            if isPercentage {
                Task {
                    try? await Task.sleep(for: .seconds(0.15))
                    oilWeightFocused = true
                }
            }
        }
    }

    /// The single-lye rows are toggle, lye type, soap type, ingredient,
    /// purity, water and super fat; dual lye swaps the middle four for the
    /// split, both purities and both ingredients.
    private var lyeSection: some View {
        Section {
            let count = model.useHybrid ? 10 : 7
            sheetRow(0, of: count) {
                toggleRow("Dual lye (NaOH + KOH)", isOn: $model.useHybrid)
            }
            if model.useHybrid {
                sheetRow(1, of: count) { soapTypeRow }
                sheetRow(2, of: count) {
                    percentRow("KOH", value: Binding(get: { model.kohPercentage }, set: model.setKOHPercentage), prompt: "0")
                }
                sheetRow(3, of: count) {
                    percentRow("NaOH", value: Binding(get: { model.naohPercentage }, set: model.setNaOHPercentage), prompt: "0")
                }
                sheetRow(4, of: count) { percentRow("KOH purity", value: $model.kohPurity, prompt: "90") }
                sheetRow(5, of: count) { percentRow("NaOH purity", value: $model.naohPurity, prompt: "99") }
                sheetRow(6, of: count) { lyeIngredientRow("KOH ingredient", selected: $model.kohLyeIngredient) }
                sheetRow(7, of: count) { lyeIngredientRow("NaOH ingredient", selected: $model.lyeIngredient) }
            } else {
                sheetRow(1, of: count) {
                    HoneyLedgerSegmented(
                        "Lye type",
                        selection: Binding(get: { model.lyeType }, set: model.setLyeType),
                        options: [("NaOH", "NaOH"), ("KOH", "KOH")]
                    )
                }
                sheetRow(2, of: count) { soapTypeRow }
                sheetRow(3, of: count) {
                    lyeIngredientRow(
                        "Lye ingredient",
                        selected: model.lyeType == "KOH" ? $model.kohLyeIngredient : $model.lyeIngredient
                    )
                }
                sheetRow(4, of: count) { percentRow("Lye purity", value: $model.lyePurity, prompt: "99") }
            }
            sheetRow(count - 2, of: count) { waterRatioRow }
            sheetRow(count - 1, of: count) { percentRow("Super Fat", value: $model.superFat, prompt: "5") }
        } header: {
            HoneyLedgerSectionLabel("Lye configuration")
        }
        .animation(.default, value: model.useHybrid)
    }

    private var soapTypeRow: some View {
        HoneyLedgerCalculatedRow(title: "Soap type", value: model.soapType.label)
    }

    private var soapMethodSection: some View {
        Section {
            let showsCFM = model.soapType != .solid
            let count = 1 + (showsCFM ? 1 : 0) + (showsCFM && model.useCFM ? 2 : 0)
            sheetRow(0, of: count) {
                infoToggleRow(
                    "Cream soap method",
                    explanation: creamSoapExplanation,
                    isOn: Binding(
                        get: { model.isCreamSoap },
                        set: { model.setCreamSoap($0, from: allIngredients) }
                    )
                )
            }
            // The Catherine Failor method only makes sense for non-solid soaps
            // (single KOH or dual lye), so it's hidden for a solid NaOH bar.
            if showsCFM {
                sheetRow(1, of: count) {
                    infoToggleRow("Catherine Failor method", explanation: cfmExplanation, isOn: $model.useCFM)
                }
                if model.useCFM {
                    sheetRow(2, of: count) {
                        HoneyLedgerSegmented(
                            "Neutraliser",
                            selection: Binding(
                                get: { model.cfmNeutralizer },
                                set: { model.setCFMNeutralizer($0, from: additiveIngredients) }
                            ),
                            options: CFMNeutralizer.allCases.map { ($0, $0.displayName) }
                        )
                    }
                    sheetRow(3, of: count) { neutralizerIngredientRow }
                }
            }
        } header: {
            HoneyLedgerSectionLabel("Soap method")
        } footer: {
            if model.soapType == .solid {
                footer("The Catherine Failor liquid-soap method appears when the recipe makes a liquid "
                       + "or cream soap — switch to KOH or dual lye.")
            } else if model.useCFM && model.neutralizerIngredient == nil {
                footer("The neutraliser dose is shown in the amounts table, but without an ingredient "
                       + "it isn't costed or deducted from inventory when you make a batch.")
            }
        }
        .animation(.default, value: model.useCFM)
        .animation(.default, value: model.soapType)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .foregroundStyle(Color.ink)
            .tint(Color.amber)
    }

    /// The info icon is a sibling of the toggle rather than part of its label,
    /// which would swallow the tap.
    private func infoToggleRow(_ title: String, explanation: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.ink)
            InfoPopoverIcon(title: title, text: explanation)
            Spacer()
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .tint(Color.amber)
        }
    }

    /// A menu rather than a `Picker`: a menu picker draws its value in the
    /// accent colour, and amber is only ever a fill.
    private func unitMenu(_ title: String, units: [String], selection: Binding<String>) -> some View {
        Menu {
            ForEach(units, id: \.self) { unit in
                Button { selection.wrappedValue = unit } label: {
                    MenuSelectionLabel(unit, isSelected: selection.wrappedValue == unit)
                }
            }
        } label: {
            PickerMenuRowLabel(title: title, value: selection.wrappedValue)
        }
        .tint(.primary)
    }

    private func percentRow(_ label: String, value: Binding<Double>, prompt: String) -> some View {
        HoneyLedgerField(label, unit: "%") { focus in
            NumericTextField(prompt: prompt, value: value, fillsAvailableWidth: true, focus: focus)
        }
    }

    /// Built by the same helper as the lye rows so the three pickers stay
    /// identical. The unresolved-neutraliser note lives in the section footer.
    private var neutralizerIngredientRow: some View {
        ingredientPickerRow("Neutraliser ingredient", selected: $model.neutralizerIngredient, config: .neutralizer)
    }

    private func lyeIngredientRow(_ label: String, selected: Binding<Ingredient?>) -> some View {
        ingredientPickerRow(label, selected: selected, config: .lye)
    }

    private func ingredientPickerRow(
        _ label: String,
        selected: Binding<Ingredient?>,
        config: CategoryIngredientPickerConfig
    ) -> some View {
        NavigationLink {
            CategoryIngredientPickerView(selected: selected, config: config)
        } label: {
            // Stacked so a long ingredient name (e.g. "Potassium Hydroxide
            // (Lye)") wraps under the label instead of overflowing on narrow
            // iPhone widths.
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .foregroundStyle(Color.ink)
                Text(selected.wrappedValue?.name ?? "Select…")
                    .font(.subheadline)
                    .fontWeight(selected.wrappedValue == nil ? .regular : .medium)
                    .foregroundStyle(selected.wrappedValue == nil ? Color.inkFaint : Color.inkSoft)
            }
        }
    }

    private var waterRatioRow: some View {
        HoneyLedgerField("Water to lye ratio", unit: ": 1") { focus in
            NumericTextField(prompt: 1.5.formatted(), value: $model.waterParts, width: 30,
                             fillsAvailableWidth: true, focus: focus)
        }
    }

    private var fragranceSection: some View {
        Section {
            percentRow("EO / Fragrances", value: $model.fragrancePercentage, prompt: "3")
                .ledgerSheetRow(position: .only)
        } header: {
            HoneyLedgerSectionLabel("Fragrance configuration")
        } footer: {
            footer("The share of \(model.makesSoap ? "total oil weight" : "total weight") kept for "
                   + "essential and fragrance oils, used for the recommended amount on the Ingredients tab.")
        }
    }
}
