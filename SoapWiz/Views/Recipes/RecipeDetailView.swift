import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    let recipe: Recipe

    @Environment(AppNavigation.self) private var navigation

    @Query(filter: RecipeDetailView.lyesPredicate)
    private var lyeIngredients: [Ingredient]
    @Query private var settingsRecords: [AppSettings]

    @State private var model = RecipeFormViewModel()
    @State private var showEdit = false
    @State private var selectedQualityName: String?
    @State private var batchTotalExpanded = false
    @State private var expandedProducts: [PersistentIdentifier: Bool] = [:]
    @State private var showInGrams = false
    @State private var showCreateBatch = false

    /// The unit the summaries (calculated amounts + cost breakdown) are shown in:
    /// the recipe's oil weight unit, or grams when the user toggles it.
    private var displayUnit: String { showInGrams ? "g" : model.displayWeightUnit }

    /// Offer the grams toggle only when the recipe isn't already measured in grams.
    private var showsUnitToggle: Bool { model.displayWeightUnit != "g" }

    /// Converts an amount expressed in the oil weight unit into the chosen display unit.
    private func displayed(_ batchAmount: Double) -> Double {
        MassUnitConverter.convert(batchAmount, from: model.displayWeightUnit, to: displayUnit) ?? batchAmount
    }

    /// Formats an oil-unit amount in the chosen display unit, with the unit label.
    private func weightText(_ batchAmount: Double) -> String {
        "\(displayed(batchAmount).formatted(.number.precision(.fractionLength(0...2)))) \(displayUnit)"
    }

    private static let lyesPredicate: Predicate<Ingredient> = {
        let name = IngredientCategory.Name.lyes
        return #Predicate { $0.category?.name == name }
    }()

    var body: some View {
        let batch = model.wholeBatchBreakdown
        Form {
            if !recipe.desc.isEmpty {
                Section {
                    Text(recipe.desc)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.cardBackground)
            }

            oilsSection
            additivesSection(batch: batch)
            fragrancesSection(batch: batch)
            calculatedAmountsSection
            soapPropertiesSection
            costSection(batch: batch)
        }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .warmNavigationTitle(recipe.name)
        .warmBackground()
        .safeAreaInset(edge: .bottom) {
            Button {
                showCreateBatch = true
            } label: {
                Label("Create Batch", systemImage: "bubbles.and.sparkles.fill")
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
            }
            .glassButtonStyleIOS26()
            .controlSize(.large)
            .padding(.bottom, 8)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { showEdit = true }
            }
        }
        .sheet(isPresented: $showCreateBatch) {
            CreateBatchSheet(recipe: recipe, lyeCandidates: lyeIngredients) { batch in
                navigation.showBatch(batch)
            }
        }
        .sheet(isPresented: $showEdit, onDismiss: {
            model.load(from: recipe)
            model.resolveDefaultLyeIngredient(from: lyeIngredients)
        }) {
            NavigationStack {
                RecipeFormView(recipe: recipe)
            }
        }
        .task(id: recipe.persistentModelID) {
            model.load(from: recipe)
            model.resolveDefaultLyeIngredient(from: lyeIngredients)
        }
        .onChange(of: lyeIngredients) {
            model.resolveDefaultLyeIngredient(from: lyeIngredients)
        }
    }

    // MARK: - Oils

    private var sortedOils: [OilIngredientDraft] {
        model.oilDrafts.sorted { $0.amount > $1.amount }
    }

    private var oilBatchWeightByDraftId: [UUID: Double] {
        Dictionary(uniqueKeysWithValues: (model.oilAmountCalculations ?? []).map { ($0.id, $0.weight) })
    }

    private var oilsSection: some View {
        let weightLookup = oilBatchWeightByDraftId
        return Section("Oils") {
            if sortedOils.isEmpty {
                Text("No oils added")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedOils) { draft in
                    HStack {
                        Text(draft.ingredient.name)
                        Spacer()
                        Text(oilAmountText(draft, batchWeight: weightLookup[draft.id]))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .listRowBackground(Color.cardBackground)
    }

    private func oilAmountText(_ draft: OilIngredientDraft, batchWeight: Double?) -> String {
        if model.weightUnitIsPercentage {
            let primary = model.formatPercentage(draft.amount) + "%"
            guard let batchWeight else { return primary }
            return "\(primary) (\(weightText(batchWeight)))"
        }
        // Absolute mode: the entered amount is already in the oil weight unit.
        return weightText(batchWeight ?? draft.amount)
    }

    /// Maps each breakdown row's ingredient to its amount in the oil weight unit.
    private func batchWeightLookup(_ rows: [IngredientProductBreakdown]) -> [PersistentIdentifier: Double] {
        Dictionary(uniqueKeysWithValues: rows.map { ($0.ingredient.persistentModelID, $0.ingredientAmount) })
    }

    // MARK: - Additives

    @ViewBuilder
    private func additivesSection(batch: ProductCostBreakdown) -> some View {
        if !model.additiveDrafts.isEmpty {
            let weightLookup = batchWeightLookup(batch.additives)
            Section("Additives") {
                ForEach(model.additiveDrafts) { draft in
                    HStack {
                        Text(draft.ingredient.name)
                        Spacer()
                        Text(ingredientAmountText(draft, batchWeight: weightLookup[draft.ingredient.persistentModelID]))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .listRowBackground(Color.cardBackground)
        }
    }

    // MARK: - Fragrances

    @ViewBuilder
    private func fragrancesSection(batch: ProductCostBreakdown) -> some View {
        if !model.fragranceDrafts.isEmpty {
            let weightLookup = batchWeightLookup(batch.fragrances)
            Section("Fragrances") {
                ForEach(model.fragranceDrafts) { draft in
                    HStack {
                        Text(draft.ingredient.name)
                        Spacer()
                        Text(ingredientAmountText(draft, batchWeight: weightLookup[draft.ingredient.persistentModelID]))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .listRowBackground(Color.cardBackground)
        }
    }

    /// Shows the converted weight in parentheses only when the ingredient is
    /// expressed as a percentage; absolute units (g, kg, ml, …) stand alone.
    private func ingredientAmountText(_ draft: IngredientAmountDraft, batchWeight: Double?) -> String {
        let primary = amountText(draft.amount, unit: draft.unit)
        guard draft.unit.hasPrefix("%"), let batchWeight, batchWeight > 0 else { return primary }
        return "\(primary) (\(weightText(batchWeight)))"
    }

    private func amountText(_ amount: Double, unit: String) -> String {
        let fmt = amount.formatted(.number.precision(.fractionLength(0...2)))
        return "\(fmt) \(unit)"
    }

    // MARK: - Calculated amounts

    @ViewBuilder
    private var unitTogglePicker: some View {
        if showsUnitToggle {
            Picker("Units", selection: $showInGrams) {
                Text(model.displayWeightUnit).tag(false)
                Text("g").tag(true)
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var calculatedAmountsSection: some View {
        Section("Calculated amounts") {
            if let rows = model.calculatedAmountRows {
                unitTogglePicker
                ForEach(rows) { row in
                    HStack {
                        Text(row.label)
                            .fontWeight(row.isSummary ? .semibold : .regular)
                        Spacer()
                        Text(weightText(row.weight))
                            .foregroundStyle(row.isSummary ? .primary : .secondary)
                            .monospacedDigit()
                    }
                }
            } else {
                Text("Add oils to see calculated amounts")
                    .foregroundStyle(.secondary)
            }
        }
        .listRowBackground(Color.cardBackground)
    }

    // MARK: - Soap properties

    private var selectedQuality: SoapQuality? {
        guard let name = selectedQualityName else { return nil }
        return SoapQuality.allCases.first { $0.displayName == name }
    }

    private var soapPropertiesSection: some View {
        let stats = RecipeStats(oilDrafts: model.oilDrafts)
        return Section("Soap properties") {
            if stats.hasOils {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Grey bands show the recommended range for each property.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    SoapPropertiesChartView(
                        profile: stats.fattyAcidProfile,
                        hasOils: stats.hasOils,
                        selectedDisplayName: $selectedQualityName
                    )
                }
                .padding(.vertical, 4)

                if let quality = selectedQuality {
                    OilContributionCardView(
                        quality: quality,
                        totalValue: quality.value(from: stats.fattyAcidProfile),
                        contributions: stats.contributions(for: quality),
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                selectedQualityName = nil
                            }
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                HStack {
                    Text("INS")
                    Spacer()
                    Text(stats.ins.formatted(.number.precision(.fractionLength(0...1))))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack {
                    Text("Iodine value")
                    Spacer()
                    Text(stats.iodineValue.formatted(.number.precision(.fractionLength(0...1))))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else {
                Text("Add oils to see soap properties")
                    .foregroundStyle(.secondary)
            }
        }
        .listRowBackground(Color.cardBackground)
    }
}

// MARK: - Cost

private extension RecipeDetailView {
    static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()

    private static let amountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private var pvpFactor: Double { settingsRecords.first?.pvpFactor ?? 4.0 }

    private var nonWholeBatchProducts: [RecipeProductDraft] {
        model.productDrafts.filter { draft in
            let unit = ProductUnit(rawValue: draft.unitSymbol)
            if unit == .wholeBatch { return false }
            if unit == .partsOfBatch && draft.size <= 1 { return false }
            return true
        }
    }

    private func productBreakdowns(batch: ProductCostBreakdown) -> [UUID: ProductCostBreakdown] {
        Dictionary(uniqueKeysWithValues: nonWholeBatchProducts.map { draft in
            (draft.id, model.breakdownAndCost(for: draft, batch: batch))
        })
    }

    private func isExpanded(modelID: PersistentIdentifier) -> Binding<Bool> {
        Binding(
            get: { expandedProducts[modelID] ?? false },
            set: { expandedProducts[modelID] = $0 }
        )
    }

    private func productLabel(_ draft: RecipeProductDraft) -> String {
        guard let unit = ProductUnit(rawValue: draft.unitSymbol) else {
            return draft.unitSymbol
        }
        if unit == .partsOfBatch {
            return "1/\(Int(draft.size)) batch"
        }
        let sizeFmt = Self.amountFormatter.string(from: NSNumber(value: draft.size)) ?? "\(draft.size)"
        return "\(sizeFmt) \(draft.unitSymbol)"
    }

    private func formatCurrency(_ value: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: value)) ?? "—"
    }

    private func costSection(batch: ProductCostBreakdown) -> some View {
        Section("Cost breakdown") {
            let batchTotal = batch.total
            if batchTotal > 0 {
                DisclosureGroup(isExpanded: $batchTotalExpanded) {
                    productBreakdownRows(batch)
                } label: {
                    HStack {
                        Text("Batch total")
                            .fontWeight(.semibold)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(formatCurrency(batchTotal))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                            Text("RRP \(formatCurrency(batchTotal * pvpFactor))")
                                .font(.caption)
                                .foregroundStyle(.tint)
                                .monospacedDigit()
                        }
                    }
                }
            } else {
                Text("No cost data — add purchase prices in Inventory")
                    .foregroundStyle(.secondary)
            }

            let breakdowns = productBreakdowns(batch: batch)
            ForEach(nonWholeBatchProducts, id: \.id) { draft in
                if let modelID = draft.modelID, let breakdown = breakdowns[draft.id], breakdown.total > 0 {
                    DisclosureGroup(isExpanded: isExpanded(modelID: modelID)) {
                        productBreakdownRows(breakdown)
                    } label: {
                        productDisclosureLabel(draft, breakdown: breakdown)
                    }
                }
            }
        }
        .listRowBackground(Color.cardBackground)
    }

    private func productDisclosureLabel(_ draft: RecipeProductDraft, breakdown: ProductCostBreakdown) -> some View {
        HStack {
            Text(productLabel(draft))
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(formatCurrency(breakdown.total))
                    .font(.subheadline)
                    .monospacedDigit()
                Text("RRP \(formatCurrency(breakdown.total * pvpFactor))")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .monospacedDigit()
            }
        }
    }

    private func productBreakdownRows(_ breakdown: ProductCostBreakdown) -> some View {
        let groups: [(name: String, usesEnteredUnit: Bool, rows: [IngredientProductBreakdown])] = [
            ("Oils", false, breakdown.oils),
            ("Additives", true, breakdown.additives),
            ("Fragrances", true, breakdown.fragrances),
            ("Lye", false, breakdown.lye),
        ].filter { !$0.rows.isEmpty }

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(groups, id: \.name) { group in
                Text(group.name)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                ForEach(group.rows, id: \.ingredient.persistentModelID) { row in
                    let display = model.displayedAmount(for: row, usesEnteredUnit: group.usesEnteredUnit)
                    HStack(spacing: 8) {
                        Text(row.ingredient.name)
                            .font(.footnote)
                        Spacer()
                        if let note = display.conversionNote {
                            InfoPopoverIcon(text: note)
                        }
                        Text(amountText(display.amount, unit: display.unit))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        if row.cost > 0 {
                            Text(formatCurrency(row.cost))
                                .font(.footnote)
                                .monospacedDigit()
                                .frame(width: 64, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
    }
}
