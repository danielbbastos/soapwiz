import SwiftUI
import SwiftData

private enum RecipeTab: String, CaseIterable {
    case config = "Config"
    case ingredients = "Ingredients"
    case stats = "Stats"
}

private let weightUnits = ["g", "oz", "lb", "kg", "%"]
private let absoluteWeightUnits = ["g", "oz", "lb", "kg"]

struct RecipeFormView: View {
    private static let lyesPredicate: Predicate<Ingredient> = {
        let name = IngredientCategory.Name.lyes
        return #Predicate { $0.category?.name == name }
    }()

    var recipe: Recipe?
    var seed: RecipeSeed?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(filter: lyesPredicate)
    private var lyeIngredients: [Ingredient]

    @State private var model = RecipeFormViewModel()
    @State private var selectedTab: RecipeTab = .config
    @State private var showFragranceInfo = false
    @State private var showMoldCalculator = false
    @FocusState private var oilWeightFocused: Bool

    var onSave: ((Recipe) -> Void)?

    var body: some View {
        currentTab
            .scrollContentBackground(.hidden)
            .background(Color.warmBackground.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                tabPicker
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            .navigationTitle(recipe == nil ? "New Recipe" : "Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle(recipe == nil ? "New Recipe" : "Edit Recipe")
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
                guard let field = note.object as? UITextField,
                      field.keyboardType == .decimalPad else { return }
                Task { @MainActor in
                    field.selectedTextRange = field.textRange(from: field.endOfDocument, to: field.endOfDocument)
                }
            }
            .task(id: recipe?.persistentModelID) {
                if let recipe { model.load(from: recipe) }
                if let seed { model.applySeed(seed.ingredients) }
                model.resolveDefaultLyeIngredient(from: lyeIngredients)
            }
            .onChange(of: lyeIngredients) {
                model.resolveDefaultLyeIngredient(from: lyeIngredients)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let recipe = model.save(context: modelContext)
                        onSave?(recipe)
                        dismiss()
                    }
                    .disabled(!model.canSave)
                }
            }
    }

    @ViewBuilder
    private var currentTab: some View {
        switch selectedTab {
        case .config: configTab
        case .ingredients: ingredientsTab
        case .stats: statsTab
        }
    }

    /// The segmented control gets an opaque fill shaped to the control itself,
    /// so scrolled content never shows through the pill while the header band
    /// around it keeps the system's scroll-under glass effect.
    @ViewBuilder
    private var tabPicker: some View {
        let picker = Picker("Tab", selection: $selectedTab) {
            ForEach(RecipeTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)

        if #available(iOS 26, *) {
            picker.background(Color.warmBackground, in: .capsule)
        } else {
            picker.background(Color.warmBackground, in: .rect(cornerRadius: 8))
        }
    }
}

// MARK: - Config Tab

private extension RecipeFormView {
    var configTab: some View {
        Form {
            detailsSection
            weightSection
            lyeSection
            soapMethodSection
            fragranceSection
        }
        .scrollClipDisabled()
        .sheet(isPresented: $showFragranceInfo) {
            VStack(alignment: .leading, spacing: 12) {
                Text("EO / Fragrances %")
                    .font(.headline)
                Text("The target percentage of total oil weight reserved for essential oils and fragrance oils. "
                     + "Used to calculate the recommended amount and to track usage in the Ingredients tab.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .presentationDetents([.fraction(0.3)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showMoldCalculator) {
            MoldCalculatorView(oilWeightUnit: model.oilWeightUnit) { weight in
                model.totalOilWeight = weight
            }
        }
    }

    var detailsSection: some View {
        Section("Details") {
            TextField("Name", text: $model.name)
            TextField("Description", text: $model.desc, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    var weightSection: some View {
        Section("Oils weight & unit") {
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
                    Text("Total oil weight")
                    Spacer()
                    TextField("0", value: $model.totalOilWeight, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .focused($oilWeightFocused)
                    Picker("Oil unit", selection: $model.oilWeightUnit) {
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

    var lyeSection: some View {
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

    var soapMethodSection: some View {
        Section {
            Toggle("Cream soap additions", isOn: $model.isCreamSoap)
            // The Catherine Failor method only makes sense for non-solid soaps
            // (single KOH or dual lye), so it's hidden for a solid NaOH bar.
            if model.soapType != .solid {
                Toggle("Catherine Failor method", isOn: $model.useCFM)
                if model.useCFM {
                    Picker("Neutraliser", selection: $model.cfmNeutralizer) {
                        ForEach(CFMNeutralizer.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        } header: {
            Text("Soap method")
        } footer: {
            if model.soapType == .solid {
                Text("The Catherine Failor liquid-soap method appears when the recipe makes a liquid or cream soap — switch to KOH or dual lye.")
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
            TextField("0", value: Binding(get: { value }, set: set), format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
            Text("%")
                .foregroundStyle(.secondary)
        }
    }

    private func purityRow(_ label: String, value: Binding<Double>, prompt: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(prompt, value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
            Text("%")
                .foregroundStyle(.secondary)
        }
    }

    private func lyeIngredientRow(_ label: String, selected: Binding<Ingredient?>) -> some View {
        NavigationLink {
            LyeIngredientPickerView(selected: selected)
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
            TextField("1.5", value: $model.waterParts, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(width: 30)
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
            TextField("5", value: $model.superFat, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
            Text("%")
                .foregroundStyle(.secondary)
        }
    }

    var fragranceSection: some View {
        Section("Fragrance configuration") {
            HStack {
                Text("EO / Fragrances")
                Button {
                    showFragranceInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Spacer()
                TextField("3", value: $model.fragrancePercentage, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Text("%")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Ingredients Tab

private extension RecipeFormView {
    var ingredientsTab: some View {
        RecipeIngredientsTabView(model: model)
    }
}

// MARK: - Stats Tab

private extension RecipeFormView {
    var statsTab: some View {
        RecipeStatsTabView(model: model)
    }
}
