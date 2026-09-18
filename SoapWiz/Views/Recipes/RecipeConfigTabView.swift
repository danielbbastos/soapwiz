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

    private var detailsSection: some View {
        Section("Details") {
            TextField("Name", text: $model.name)
            TextField("Description", text: $model.desc, axis: .vertical)
                .lineLimit(3...6)
            PhotoField(imageData: $model.imageData)
            collectionsMenu
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
            Toggle("Non-soap product", isOn: $model.isNonSoapProduct)
        } footer: {
            if model.isNonSoapProduct {
                Text("Lye, water, super fat and the soap method options don't apply to "
                     + "candles, balms and salves, so they're hidden. Their settings are kept "
                     + "in case you switch back.")
            }
        }
    }

    private var weightSection: some View {
        Section(model.makesSoap ? "Oils weight & unit" : "Weight & unit") {
            HStack {
                Text("Measurement unit")
                Spacer()
                Picker("Unit", selection: $model.weightUnit) {
                    ForEach(weightUnits, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(.primary)
            }

            if model.weightUnitIsPercentage {
                HStack {
                    Text(model.baseWeightLabel)
                    Spacer()
                    NumericTextField(prompt: "0", value: $model.totalOilWeight,
                                     width: 80, focus: $oilWeightFocused)
                    Picker(model.baseWeightLabel, selection: $model.oilWeightUnit) {
                        ForEach(absoluteWeightUnits, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(.primary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))

                Button {
                    showMoldCalculator = true
                } label: {
                    Text("Calculate from mold…")
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
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

    private var lyeSection: some View {
        Section("Lye configuration") {
            Toggle("Dual lye (NaOH + KOH)", isOn: $model.useHybrid)

            HStack {
                Text("Soap type")
                Spacer()
                Text(model.soapType.label)
                    .foregroundStyle(.secondary)
            }

            if model.useHybrid {
                hybridLyeRows
            } else {
                singleLyeRows
            }

            waterRatioRow
            superFatRow
        }
        .animation(.default, value: model.useHybrid)
    }

    private var soapMethodSection: some View {
        Section {
            Toggle("Cream soap additions", isOn: $model.isCreamSoap)
            // The Catherine Failor method only makes sense for non-solid soaps
            // (single KOH or dual lye), so it's hidden for a solid NaOH bar.
            if model.soapType != .solid {
                // The info icon is a sibling of the toggle rather than part of
                // its label, which would swallow the tap.
                HStack {
                    Text("Catherine Failor method")
                    InfoPopoverIcon(title: "Catherine Failor method", text: cfmExplanation)
                    Spacer()
                    Toggle("Catherine Failor method", isOn: $model.useCFM)
                        .labelsHidden()
                }
                if model.useCFM {
                    Picker("Neutraliser", selection: Binding(
                        get: { model.cfmNeutralizer },
                        set: { model.setCFMNeutralizer($0, from: additiveIngredients) }
                    )) {
                        ForEach(CFMNeutralizer.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    neutralizerIngredientRow
                }
            }
        } header: {
            Text("Soap method")
        } footer: {
            if model.soapType == .solid {
                Text("The Catherine Failor liquid-soap method appears when the recipe makes a liquid "
                     + "or cream soap — switch to KOH or dual lye.")
            } else if model.useCFM && model.neutralizerIngredient == nil {
                Text("The neutraliser dose is shown in the amounts table, but without an ingredient "
                     + "it isn't costed or deducted from inventory when you make a batch.")
            }
        }
        .animation(.default, value: model.useCFM)
        .animation(.default, value: model.soapType)
    }

    @ViewBuilder
    private var singleLyeRows: some View {
        HStack {
            Text("Lye type")
            Spacer()
            Picker("Lye type", selection: Binding(get: { model.lyeType }, set: model.setLyeType)) {
                Text("NaOH").tag("NaOH")
                Text("KOH").tag("KOH")
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(.primary)
        }
        lyeIngredientRow(
            "Lye ingredient",
            selected: model.lyeType == "KOH" ? $model.kohLyeIngredient : $model.lyeIngredient
        )
        purityRow("Lye purity", value: $model.lyePurity, prompt: "99")
    }

    @ViewBuilder
    private var hybridLyeRows: some View {
        percentageRow("KOH", value: model.kohPercentage, set: model.setKOHPercentage)
        percentageRow("NaOH", value: model.naohPercentage, set: model.setNaOHPercentage)
        purityRow("KOH purity", value: $model.kohPurity, prompt: "90")
        purityRow("NaOH purity", value: $model.naohPurity, prompt: "99")
        lyeIngredientRow("KOH ingredient", selected: $model.kohLyeIngredient)
        lyeIngredientRow("NaOH ingredient", selected: $model.lyeIngredient)
    }

    private func percentageRow(_ label: String, value: Double, set: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(label)
            Spacer()
            NumericTextField(prompt: "0", value: Binding(get: { value }, set: set))
            Text("%")
                .foregroundStyle(.secondary)
        }
    }

    private func purityRow(_ label: String, value: Binding<Double>, prompt: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            NumericTextField(prompt: prompt, value: value)
            Text("%")
                .foregroundStyle(.secondary)
        }
    }

    /// Built by the same helper as the lye rows so the three pickers stay
    /// identical. The unresolved-neutraliser note lives in the section footer.
    private var neutralizerIngredientRow: some View {
        ingredientPickerRow(
            "Neutraliser ingredient",
            selected: $model.neutralizerIngredient,
            category: IngredientCategory.Name.additives,
            navigationTitle: "Neutraliser ingredient",
            emptyTitle: "No additives",
            emptyDescription: "Add an ingredient to the \"Additives\" category."
        )
    }

    private func lyeIngredientRow(_ label: String, selected: Binding<Ingredient?>) -> some View {
        ingredientPickerRow(
            label,
            selected: selected,
            category: IngredientCategory.Name.lyes,
            navigationTitle: "Lye ingredient",
            emptyTitle: "No lye ingredients",
            emptyDescription: "Add an ingredient to the \"Lyes\" category."
        )
    }

    private func ingredientPickerRow(
        _ label: String,
        selected: Binding<Ingredient?>,
        category: String,
        navigationTitle: String,
        emptyTitle: String,
        emptyDescription: String
    ) -> some View {
        NavigationLink {
            CategoryIngredientPickerView(
                selected: selected,
                category: category,
                navigationTitle: navigationTitle,
                emptyTitle: emptyTitle,
                emptyDescription: emptyDescription
            )
        } label: {
            // Stacked so a long ingredient name (e.g. "Potassium Hydroxide
            // (Lye)") wraps under the label instead of overflowing on narrow
            // iPhone widths.
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                Text(selected.wrappedValue?.name ?? "Select…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var waterRatioRow: some View {
        HStack {
            Text("Water to lye ratio")
            Spacer()
            NumericTextField(prompt: "1.5", value: $model.waterParts, width: 30, alignment: .center)
            Text(":")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            Text("1")
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .center)
        }
    }

    private var superFatRow: some View {
        HStack {
            Text("Super Fat")
            Spacer()
            NumericTextField(prompt: "5", value: $model.superFat)
            Text("%")
                .foregroundStyle(.secondary)
        }
    }

    /// Liquid-soap method described in Catherine Failor's *Making Natural Liquid
    /// Soaps*, as implemented in `LyeCalculator`. The dose is quoted in the
    /// recipe's own units: Failor's ¾ oz per lb when the recipe is measured in
    /// oz or lb, the metric equivalent otherwise.
    private var cfmExplanation: String {
        "Takes the lye at 0% super fat plus a 10% excess so every oil saponifies, "
        + "then neutralises what's left over after the cook. Water is still sized "
        + "from the recipe's normal super-fat lye, so the excess doesn't dilute the batch.\n\n"
        + "The neutraliser is \(cfmDoseDescription) — boric acid at 20% solid "
        + "to 80% water, or borax at 33% to 67%. The dose is shown with the calculated "
        + "amounts and, once a neutraliser ingredient is chosen, costed and deducted "
        + "from inventory like the lye."
    }

    /// Failor's ¾ oz of solution per lb of soap, or the same fraction expressed
    /// as grams per kilogram for a metric recipe — derived from the calculator's
    /// constant rather than typed out, so the two can't drift apart.
    private var cfmDoseDescription: String {
        if model.usesImperialUnits {
            return "¾ oz of solution per lb of soap"
        }
        let gramsPerKilogram = (LyeCalculator.cfmNeutralizerSolutionFraction * 1000)
            .formatted(.number.precision(.fractionLength(0)))
        return "about \(gramsPerKilogram) g of solution per kg of soap"
    }

    private var fragranceSection: some View {
        Section("Fragrance configuration") {
            HStack {
                Text("EO / Fragrances")
                InfoPopoverIcon(
                    title: "EO / Fragrances %",
                    text: "The target percentage of \(model.makesSoap ? "total oil weight" : "total weight") "
                        + "reserved for essential oils and fragrance oils. Used to calculate the "
                        + "recommended amount and to track usage in the Ingredients tab."
                )
                Spacer()
                NumericTextField(prompt: "3", value: $model.fragrancePercentage)
                Text("%")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
