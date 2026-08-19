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
}

struct RecipeIngredientsTabView: View {
    @Bindable var model: RecipeFormViewModel
    @Query(sort: \Ingredient.name) private var inventory: [Ingredient]
    @State private var activePicker: PickerSection?
    @State private var oilsExpanded = true
    @State private var ingredientsExpanded = true
    @State private var additivesExpanded = true
    @State private var fragrancesExpanded = true
    @State private var calculatedAmountsExpanded = true
    @State private var costBreakdownExpanded = false
    @State private var availableHeight: CGFloat = 0

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
            calculatedAmountsSection
            RecipeExtraIngredientsSection(model: model)
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
            CostBreakdownBarView(model: model, isExpanded: $costBreakdownExpanded, availableHeight: availableHeight)
                .expandingSectionScrollOverlay()
        }
        .expandingSectionScrollContainer()
        .sheet(item: $activePicker) { section in
            IngredientPickerView(
                addedIDs: addedIDs(for: section),
                allowedRoles: section.roles,
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
                .expandingSectionEnd(RecipeFormSection.oils, if: model.oilDrafts.isEmpty)
                ForEach(model.oilDrafts) { draft in
                    baseRow(draft)
                        .expandingSectionEnd(
                            RecipeFormSection.oils, if: draft.id == model.oilDrafts.last?.id
                        )
                }
                .onDelete { model.removeOil(at: $0) }
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
                .expandingSectionEnd(
                    RecipeFormSection.ingredients,
                    if: model.oilDrafts.isEmpty && model.additiveDrafts.isEmpty
                )
                ForEach(model.oilDrafts) { draft in
                    baseRow(draft)
                        .expandingSectionEnd(
                            RecipeFormSection.ingredients,
                            if: model.additiveDrafts.isEmpty && draft.id == model.oilDrafts.last?.id
                        )
                }
                .onDelete { model.removeOil(at: $0) }
                ForEach(model.additiveDrafts) { draft in
                    HStack {
                        Text(draft.ingredient.name)
                            .lineLimit(1)
                        Spacer()
                        NumericTextField(prompt: "0", value: Binding(
                            get: { draft.amount },
                            set: { model.updateAdditive(id: draft.id, amount: $0) }
                        ), fractionLength: 0...3, width: 55)
                        // Static, not a menu: on a non-soap recipe the unit is
                        // derived from the recipe's measurement unit and the
                        // ingredient's own, so every row reads the same way and
                        // there is nothing to choose.
                        Text(model.unitLabel(for: draft.unit))
                            .foregroundStyle(.secondary)
                    }
                    .expandingSectionEnd(
                        RecipeFormSection.ingredients, if: draft.id == model.additiveDrafts.last?.id
                    )
                }
                .onDelete { model.removeAdditive(at: $0) }
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
    /// unlocked base rows to hold the scale at 100%. The caller tags it for its
    /// own section.
    private func baseRow(_ draft: OilIngredientDraft) -> some View {
        HStack {
            Text(draft.ingredient.name)
                .lineLimit(1)
            Spacer()
            NumericTextField(prompt: "0", value: Binding(
                get: { draft.amount },
                set: { model.userEdited(id: draft.id, amount: $0) }
            ))
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
                    .expandingSectionEnd(RecipeFormSection.additives, if: model.additiveDrafts.isEmpty)
                ForEach(model.additiveDrafts) { draft in
                    HStack {
                        Text(draft.ingredient.name)
                            .lineLimit(1)
                        Spacer()
                        NumericTextField(prompt: "0", value: Binding(
                            get: { draft.amount },
                            set: { model.updateAdditive(id: draft.id, amount: $0) }
                        ), fractionLength: 0...3, width: 55)
                        Picker("Unit", selection: Binding(
                            get: { draft.unit },
                            set: { model.updateAdditive(id: draft.id, unit: $0) }
                        )) {
                            ForEach(RecipeUnitOptions.additive, id: \.self) { Text($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .expandingSectionEnd(
                        RecipeFormSection.additives, if: draft.id == model.additiveDrafts.last?.id
                    )
                }
                .onDelete { model.removeAdditive(at: $0) }
            }
        }
    }

    // MARK: - Fragrances

    private var fragrancesSection: some View {
        Section(header: CollapsibleSectionHeader(title: IngredientCategory.Name.fragrances, expanded: $fragrancesExpanded)
            .expandingSectionHeader(RecipeFormSection.fragrances, expanded: fragrancesExpanded)) {
            if fragrancesExpanded {
                HStack {
                    Button {
                        activePicker = .fragrances
                    } label: {
                        Label("Add fragrance", systemImage: "plus")
                            .labelStyle(TightLabelStyle())
                    }
                    Spacer()
                    if let target = model.fragranceTarget {
                        HStack(spacing: 4) {
                            Text(target.text)
                                .foregroundStyle(target.isOverTarget ? Color.red : Color.secondary)
                            InfoPopoverIcon(text: fragranceTargetInfoText(for: target))
                        }
                    }
                    Picker("Unit", selection: Binding(
                        get: { model.fragranceUnit },
                        set: { model.setFragranceUnit($0) }
                    )) {
                        ForEach(FragranceUnit.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .expandingSectionEnd(RecipeFormSection.fragrances, if: model.fragranceDrafts.isEmpty)
                ForEach(model.fragranceDrafts) { draft in
                    HStack {
                        Text(draft.ingredient.name)
                            .lineLimit(1)
                        Spacer()
                        NumericTextField(prompt: "0", value: Binding(
                            get: { draft.amount },
                            set: { model.userEditedFragrance(id: draft.id, amount: $0) }
                        ), fractionLength: 0...3, width: 55)
                        Text(model.fragranceUnit.rawValue)
                            .foregroundStyle(.secondary)
                    }
                    // Tagged unconditionally: the tag applies an `.id`, and a
                    // condition that flips as the blend total is typed would
                    // rebuild the very field being edited and drop its focus.
                    // The warning below is left out of the measured section.
                    .expandingSectionEnd(
                        RecipeFormSection.fragrances, if: draft.id == model.fragranceDrafts.last?.id
                    )
                }
                .onDelete { model.removeFragrance(at: $0) }
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

    private func fragranceTargetInfoText(for target: FragranceTarget) -> String {
        let load = "Recommended fragrance load: "
            + "\(model.formatPercentage(target.percentage))% of total oils, "
            + "set on the Config tab."
        guard model.fragranceUnit == .percentOfFragrances else { return load }
        return load + " Each row is its share of that load; the shares should total 100%."
    }

    // MARK: - Calculated amounts

    @ViewBuilder
    private var calculatedAmountsSection: some View {
        if let rows = model.calculatedAmountRows {
            Section(header: CollapsibleSectionHeader(title: "Calculated amounts", expanded: $calculatedAmountsExpanded)
                .expandingSectionHeader(RecipeFormSection.calculatedAmounts, expanded: calculatedAmountsExpanded)) {
                if calculatedAmountsExpanded {
                    VStack(spacing: 0) {
                        amountHeader
                        ForEach(Array(rows.enumerated()), id: \.element.id) { _, row in
                            Divider().padding(.leading, row.isSummary ? 0 : 16)
                            amountRow(row.label, weight: row.weight, pct: row.pct, summary: row.isSummary)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .expandingSectionEnd(RecipeFormSection.calculatedAmounts)
                }
            }
        }
    }

    private var amountHeader: some View {
        HStack(spacing: 8) {
            Text("Ingredient")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Weight")
                .frame(width: 90, alignment: .trailing)
            Text("%")
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .font(.footnote)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
        .background(Color.cardBackground)
    }

    private func amountRow(_ label: String, weight: Double, pct: Double, summary: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
            Text(formatWeight(weight))
                .frame(width: 90, alignment: .trailing)
                .monospacedDigit()
            Text(formatPct(pct))
                .frame(width: 64, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .font(.footnote)
        .fontWeight(summary ? .medium : .regular)
        .foregroundStyle(summary ? Color.primary : Color.secondary)
    }

    private func formatWeight(_ value: Double) -> String {
        let formatted = value.formatted(.number.precision(.fractionLength(0...2)).grouping(.automatic))
        return "\(formatted) \(model.displayWeightUnit)"
    }

    private func formatPct(_ pct: Double) -> String {
        String(format: "%.1f%%", pct)
    }

    // MARK: - Helpers

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
