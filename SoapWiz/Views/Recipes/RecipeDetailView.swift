import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    let recipe: Recipe

    @Environment(AppNavigation.self) private var navigation

    @Query(filter: RecipeDetailView.lyesPredicate)
    private var lyeIngredients: [Ingredient]
    @Query private var settingsRecords: [AppSettings]

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var model = RecipeFormViewModel()
    @State private var detailWidth: Double = 0
    @State private var showEdit = false
    @State private var selectedQualityName: String?
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
        let layout = RecipeDetailLayout(sizeClass: horizontalSizeClass, width: detailWidth)
        Form {
            switch layout {
            case .sideBySideTop, .wide:
                sideBySideTopSection(batch: batch)
            case .stacked:
                if !recipe.desc.isEmpty {
                    Section {
                        descriptionRow
                    }
                    .listRowBackground(Color.cardBackground)
                }
                oilsSection
                fragrancesSection(batch: batch)
                additivesSection(batch: batch)
                calculatedAmountsSection
            }

            if layout == .wide {
                wideChartAndCostSection(batch: batch)
            } else {
                soapPropertiesSection
                RecipeCostSection(model: model, batch: batch)
            }
        }
        .onGeometryChange(for: Double.self) { proxy in
            proxy.size.width
        } action: { width in
            detailWidth = width
        }
        .warmBackground()
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .warmNavigationTitle(recipe.name)
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
        }, content: {
            NavigationStack {
                RecipeFormView(recipe: recipe)
            }
        })
        .task(id: recipe.persistentModelID) {
            model.load(from: recipe)
            model.resolveDefaultLyeIngredient(from: lyeIngredients)
        }
        .onChange(of: lyeIngredients) {
            model.resolveDefaultLyeIngredient(from: lyeIngredients)
        }
    }

    // MARK: - Side-by-side top region (regular width)

    /// Full-width description on top, then ingredient groups on the left
    /// beside calculated amounts on the right. Rendered as free-standing cards
    /// inside one full-width Form row so the chart and cost sections below can
    /// span the whole width while everything scrolls together.
    private func sideBySideTopSection(batch: ProductCostBreakdown) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 20) {
                if !recipe.desc.isEmpty {
                    RecipeDetailCard(title: nil) { descriptionRow }
                }

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 20) {
                        RecipeDetailCard(title: "Oils") { oilsRows }
                        if !model.fragranceDrafts.isEmpty {
                            RecipeDetailCard(title: "Fragrances") { fragrancesRows(batch: batch) }
                        }
                        if !model.additiveDrafts.isEmpty {
                            RecipeDetailCard(title: "Additives") { additivesRows(batch: batch) }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 20) {
                        RecipeDetailCard(title: "Calculated amounts") { calculatedAmountsRows }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var descriptionRow: some View {
        Text(recipe.desc)
            .foregroundStyle(.secondary)
    }

    // MARK: - Oils

    private var sortedOils: [OilIngredientDraft] {
        model.oilDrafts.sorted { $0.amount > $1.amount }
    }

    private var oilBatchWeightByDraftId: [UUID: Double] {
        Dictionary(uniqueKeysWithValues: (model.oilAmountCalculations ?? []).map { ($0.id, $0.weight) })
    }

    @ViewBuilder
    private var oilsRows: some View {
        let weightLookup = oilBatchWeightByDraftId
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

    private var oilsSection: some View {
        Section("Oils") {
            oilsRows
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

    private func additivesRows(batch: ProductCostBreakdown) -> some View {
        let weightLookup = batchWeightLookup(batch.additives)
        return ForEach(model.additiveDrafts) { draft in
            HStack {
                Text(draft.ingredient.name)
                Spacer()
                Text(ingredientAmountText(draft, batchWeight: weightLookup[draft.ingredient.persistentModelID]))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func additivesSection(batch: ProductCostBreakdown) -> some View {
        if !model.additiveDrafts.isEmpty {
            Section("Additives") {
                additivesRows(batch: batch)
            }
            .listRowBackground(Color.cardBackground)
        }
    }

    // MARK: - Fragrances

    private func fragrancesRows(batch: ProductCostBreakdown) -> some View {
        let weightLookup = batchWeightLookup(batch.fragrances)
        return ForEach(model.fragranceDrafts) { draft in
            HStack {
                Text(draft.ingredient.name)
                Spacer()
                Text(ingredientAmountText(draft, batchWeight: weightLookup[draft.ingredient.persistentModelID]))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func fragrancesSection(batch: ProductCostBreakdown) -> some View {
        if !model.fragranceDrafts.isEmpty {
            Section("Fragrances") {
                fragrancesRows(batch: batch)
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
    private var calculatedAmountsRows: some View {
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

    private var calculatedAmountsSection: some View {
        Section("Calculated amounts") {
            calculatedAmountsRows
        }
        .listRowBackground(Color.cardBackground)
    }

    // MARK: - Soap properties

    private var selectedQuality: SoapQuality? {
        guard let name = selectedQualityName else { return nil }
        return SoapQuality.allCases.first { $0.displayName == name }
    }

    private var soapPropertiesSection: some View {
        Section("Soap properties") {
            soapPropertiesContent
        }
        .listRowBackground(Color.cardBackground)
    }

    /// The soap-properties chart paired with the cost breakdown, side by side.
    /// Same free-standing-card trick as `sideBySideTopSection`.
    private func wideChartAndCostSection(batch: ProductCostBreakdown) -> some View {
        Section {
            HStack(alignment: .top, spacing: 16) {
                RecipeDetailCard(title: "Soap properties") {
                    soapPropertiesContent
                }
                .frame(maxWidth: .infinity)

                RecipeCostSection(model: model, batch: batch, asCard: true)
                    .frame(maxWidth: .infinity)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private var soapPropertiesContent: some View {
        let stats = RecipeStats(oilDrafts: model.oilDrafts)
        Group {
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
    }
}
