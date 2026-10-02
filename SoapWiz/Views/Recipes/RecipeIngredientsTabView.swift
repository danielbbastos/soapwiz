import SwiftUI
import SwiftData

struct AvailableHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Label style with a tighter gap between the icon and title than the default.
private struct TightLabelStyle: LabelStyle {
    var spacing: CGFloat = 4
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
            configuration.title
        }
    }
}

private enum PickerSection: String, Identifiable {
    case oils, additives, fragrances
    /// The merged section a non-soap recipe uses in place of oils + additives.
    case ingredients
    var id: String { rawValue }

    var roles: Set<RecipeIngredientRole> {
        switch self {
        case .oils: return [.oil]
        case .additives: return [.additive]
        case .fragrances: return [.fragrance]
        case .ingredients: return [.oil, .additive]
        }
    }

    /// The merged Ingredients section also offers role-less "Others" ingredients,
    /// so a general recipe isn't limited to oils and additives. Every soap-only
    /// section keeps its exact role set.
    var includesUnroled: Bool { self == .ingredients }
}

struct RecipeIngredientsTabView: View {
    @Bindable var model: RecipeFormViewModel
    /// Matches the extras table's query, so a cream-soap glycerine add that had to
    /// wait for oils can complete against the same set here.
    @Query(sort: \Ingredient.name) private var inventory: [Ingredient]
    @Query private var settingsRecords: [AppSettings]
    @State private var activePicker: PickerSection?
    @State private var oilsExpanded = true
    @State private var ingredientsExpanded = true
    @State private var additivesExpanded = true
    @State private var fragrancesExpanded = true
    @State private var costBreakdownExpanded = false
    @State private var deletedRows: [PickerSection: Int] = [:]
    @State private var availableHeight: CGFloat = 0

    private var tracksInventory: Bool { AppSettings.tracksInventory(from: settingsRecords) }

    var body: some View {
        Form {
            unresolvedLineItemsSection
            if model.makesSoap {
                oilsSection
                additivesSection
            } else {
                ingredientsSection
            }
            fragrancesSection
            RecipeCalculatedAmountsSection(model: model)
            RecipeExtraIngredientsSection(model: model)
        }
        .readableWidth()
        .onChange(of: model.totalOilBatchWeight) {
            model.reconcileCreamSoapGlycerine(from: inventory)
        }
        .scrollClipDisabled()
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: AvailableHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(AvailableHeightKey.self) { if !costBreakdownExpanded { availableHeight = $0 } }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if tracksInventory {
                CostBreakdownBarView(model: model, isExpanded: $costBreakdownExpanded, availableHeight: availableHeight)
            }
        }
        .expandingSectionScrollContainer()
        .sheet(item: $activePicker) { section in
            IngredientPickerView(
                addedIDs: addedIDs(for: section),
                allowedRoles: section.roles,
                includesUnroled: section.includesUnroled,
                onSelect: selectAction(for: section)
            )
        }
    }

    // MARK: - Unresolved line items

    @ViewBuilder
    private var unresolvedLineItemsSection: some View {
        if model.unresolvedLineItemCount > 0 {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(unresolvedLineItemsTitle)
                        Text(unresolvedLineItemsSubtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var unresolvedLineItemsTitle: String {
        model.unresolvedLineItemCount == 1
            ? "1 ingredient hasn't synced yet and isn't shown here."
            : "\(model.unresolvedLineItemCount) ingredients haven't synced yet and aren't shown here."
    }

    private var unresolvedLineItemsSubtitle: String {
        model.unresolvedLineItemCount == 1
            ? "It will be kept when you save."
            : "They will be kept when you save."
    }

    // MARK: - Oils

    private var oilsSection: some View {
        Section(header: CollapsibleSectionHeader(title: IngredientCategory.Name.oils, expanded: $oilsExpanded)
            .expandingSectionHeader(RecipeFormSection.oils, expanded: oilsExpanded)) {
            if oilsExpanded {
                HStack {
                    addButton("Add oil") { activePicker = .oils }
                    Spacer()
                    percentageTotal
                }
                ForEach(model.oilDrafts) { draft in
                    baseRow(draft)
                }
                .onDelete(perform: deletingRows(in: .oils, model.removeOil))
                .id(deletedRows[.oils, default: 0])
            }
        }
    }

    // MARK: - Ingredients (non-soap)

    /// The merged section a non-soap recipe shows in place of Oils and
    /// Additives. The split is a soap distinction — a candle's wax and its
    /// stearic acid are both just ingredients — so the two headers become one.
    ///
    /// The rows keep their stored role underneath, which is what lets a switch
    /// back to soap restore the two sections intact. Base rows still carry the
    /// redistribution that holds the formula at 100%; the rest do not.
    private var ingredientsSection: some View {
        Section(header: CollapsibleSectionHeader(title: "Ingredients", expanded: $ingredientsExpanded)
            .expandingSectionHeader(RecipeFormSection.ingredients, expanded: ingredientsExpanded)) {
            if ingredientsExpanded {
                HStack {
                    addButton("Add ingredient") { activePicker = .ingredients }
                    Spacer()
                    percentageTotal
                }
                ForEach(model.oilDrafts) { draft in
                    baseRow(draft)
                }
                .onDelete(perform: deletingRows(in: .ingredients, model.removeOil))
                .id(deletedRows[.ingredients, default: 0])
                ForEach(model.additiveDrafts) { draft in
                    RecipeAmountRow(
                        name: draft.ingredient.name,
                        amount: Binding(
                            get: { draft.amount },
                            set: { model.updateAdditive(id: draft.id, amount: $0) }
                        ),
                        fractionLength: 0...3,
                        fieldWidth: 55
                    ) {
                        // Static, not a menu: on a non-soap recipe the unit is
                        // derived from the recipe's measurement unit and the
                        // ingredient's own, so every row reads the same way and
                        // there is nothing to choose.
                        Text(model.unitLabel(for: draft.unit))
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: deletingRows(in: .ingredients, model.removeAdditive))
                .id(deletedRows[.ingredients, default: 0])
            }
        }
    }

    // MARK: - Shared rows

    private func addButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
                .labelStyle(TightLabelStyle())
        }
    }

    /// The running total of the percentage scale, green once it reaches 100.
    /// Shown only in percentage mode, and only once there is something to total.
    @ViewBuilder
    private var percentageTotal: some View {
        if model.weightUnitIsPercentage && !model.oilDrafts.isEmpty {
            Text(model.totalPercentageText)
                .foregroundStyle(abs(model.totalPercentage - 100) < 0.1 ? Color.green : Color.red)
                .frame(width: 60, alignment: .trailing)
            Text("%")
                .foregroundStyle(.secondary)
        }
    }

    /// A base-ingredient row: the amount redistributes against the other
    /// unlocked base rows to hold the scale at 100%.
    private func baseRow(_ draft: OilIngredientDraft) -> some View {
        RecipeAmountRow(
            name: draft.ingredient.name,
            amount: Binding(
                get: { draft.amount },
                set: { model.userEdited(id: draft.id, amount: $0) }
            )
        ) {
            Text(model.weightUnitIsPercentage ? "%" : model.weightUnit)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Additives

    private var additivesSection: some View {
        Section(header: CollapsibleSectionHeader(title: IngredientCategory.Name.additives, expanded: $additivesExpanded)
            .expandingSectionHeader(RecipeFormSection.additives, expanded: additivesExpanded)) {
            if additivesExpanded {
                addButton("Add additive") { activePicker = .additives }
                ForEach(model.additiveDrafts) { draft in
                    RecipeAmountRow(
                        name: draft.ingredient.name,
                        amount: Binding(
                            get: { draft.amount },
                            set: { model.updateAdditive(id: draft.id, amount: $0) }
                        ),
                        fractionLength: 0...3,
                        fieldWidth: 55
                    ) {
                        Picker("Unit", selection: Binding(
                            get: { draft.unit },
                            set: { model.updateAdditive(id: draft.id, unit: $0) }
                        )) {
                            ForEach(RecipeUnitOptions.additive, id: \.self) { Text($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
                .onDelete(perform: deletingRows(in: .additives, model.removeAdditive))
                .id(deletedRows[.additives, default: 0])
            }
        }
    }

    // MARK: - Fragrances

    private var fragrancesSection: some View {
        Section(header: CollapsibleSectionHeader(title: IngredientCategory.Name.fragrances, expanded: $fragrancesExpanded)
            .expandingSectionHeader(RecipeFormSection.fragrances, expanded: fragrancesExpanded)) {
            if fragrancesExpanded {
                RecipeFragrancesHeaderRow(model: model) {
                    addButton("Add fragrance") { activePicker = .fragrances }
                }
                ForEach(model.fragranceDrafts) { draft in
                    RecipeAmountRow(
                        name: draft.ingredient.name,
                        amount: Binding(
                            get: { draft.amount },
                            set: { model.userEditedFragrance(id: draft.id, amount: $0) }
                        ),
                        fractionLength: 0...3,
                        fieldWidth: 55
                    ) {
                        Text(model.fragranceUnit.rawValue)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: deletingRows(in: .fragrances, model.removeFragrance))
                .id(deletedRows[.fragrances, default: 0])
                blendTotalWarning
            }
        }
    }

    /// Shown when the blend shares don't add up to 100%. The maths still
    /// resolves — shares are normalised by their actual sum — so this is a
    /// nudge, not an error.
    @ViewBuilder
    private var blendTotalWarning: some View {
        if let blendTotal = model.fragranceBlendTotal, abs(blendTotal - 100) > 0.5 {
            Label {
                Text("Blend shares total \(model.formatPercentage(blendTotal))%. "
                    + "They are applied as shares of that total, not of 100%.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Helpers

    /// A swipe delete that also rebuilds `section`'s rows, which its `ForEach`
    /// keys on `deletedRows[section]`. A row deleted after an amount field was
    /// being edited can leave the list drawing the wrong ingredient in the row
    /// below it, which then ignores swipes until the rows are rebuilt (SW-204).
    /// Only the section the delete happened in is rebuilt.
    private func deletingRows(
        in section: PickerSection, _ remove: @escaping (IndexSet) -> Void
    ) -> (IndexSet) -> Void {
        { offsets in
            remove(offsets)
            deletedRows[section, default: 0] += 1
        }
    }

    private func addedIDs(for section: PickerSection) -> Set<PersistentIdentifier> {
        switch section {
        case .oils: Set(model.oilDrafts.map(\.ingredient.persistentModelID))
        case .additives: Set(model.additiveDrafts.map(\.ingredient.persistentModelID))
        case .fragrances: Set(model.fragranceDrafts.map(\.ingredient.persistentModelID))
        case .ingredients:
            Set(model.oilDrafts.map(\.ingredient.persistentModelID))
                .union(model.additiveDrafts.map(\.ingredient.persistentModelID))
        }
    }

    private func selectAction(for section: PickerSection) -> ([Ingredient]) -> Void {
        switch section {
        case .oils: { ingredients in ingredients.forEach { self.model.addOil($0) } }
        case .additives: { ingredients in ingredients.forEach { self.model.addAdditive($0) } }
        case .fragrances: { ingredients in ingredients.forEach { self.model.addFragrance($0) } }
        // Routed by the ingredient's own category, so a wax lands in the
        // percentage rows and a clay in the amount rows without the user having
        // to know the recipe still keeps them apart.
        case .ingredients: { ingredients in ingredients.forEach { self.model.addIngredient($0) } }
        }
    }
}
