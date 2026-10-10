import SwiftUI
import SwiftData

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
    /// Keeps the batch weights beside the percentages in one column.
    @ScaledMetric(relativeTo: .body) private var weightColumnWidth: CGFloat = 72

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
                config: section.pickerConfig,
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
                VStack(alignment: .leading, spacing: 4) {
                    HoneyLedgerFieldNote(unresolvedLineItemsTitle, tint: .warning)
                        .font(.body)
                    Text(unresolvedLineItemsSubtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.inkSoft)
                }
                .accessibilityElement(children: .combine)
                .ledgerSheetRow(position: .only)
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
        Section {
            if oilsExpanded {
                let count = model.oilDrafts.count + 1
                let weights = model.oilBatchWeightsByDraftID
                ForEach(Array(model.oilDrafts.enumerated()), id: \.element.id) { index, draft in
                    baseRow(draft, batchWeight: weights[draft.id])
                        .ledgerSheetRow(position: .position(index: index, count: count))
                }
                .onDelete(perform: deletingRows(in: .oils, model.removeOil))
                .id(deletedRows[.oils, default: 0])
                addButton("Add oil") { activePicker = .oils }
                    .ledgerSheetRow(position: .position(index: count - 1, count: count))
            }
        } header: {
            CollapsibleSectionHeader(title: IngredientCategory.Name.oils, expanded: $oilsExpanded)
                .expandingSectionHeader(RecipeFormSection.oils, expanded: oilsExpanded)
        } footer: {
            percentageTotal(isExpanded: oilsExpanded)
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
        Section {
            if ingredientsExpanded {
                let oilCount = model.oilDrafts.count
                let count = oilCount + model.additiveDrafts.count + 1
                let weights = model.oilBatchWeightsByDraftID
                ForEach(Array(model.oilDrafts.enumerated()), id: \.element.id) { index, draft in
                    baseRow(draft, batchWeight: weights[draft.id])
                        .ledgerSheetRow(position: .position(index: index, count: count))
                }
                .onDelete(perform: deletingRows(in: .ingredients, model.removeOil))
                .id(deletedRows[.ingredients, default: 0])
                ForEach(Array(model.additiveDrafts.enumerated()), id: \.element.id) { index, draft in
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
                            .foregroundStyle(Color.inkSoft)
                    }
                    .ledgerSheetRow(position: .position(index: oilCount + index, count: count))
                }
                .onDelete(perform: deletingRows(in: .ingredients, model.removeAdditive))
                .id(deletedRows[.ingredients, default: 0])
                addButton("Add ingredient") { activePicker = .ingredients }
                    .ledgerSheetRow(position: .position(index: count - 1, count: count))
            }
        } header: {
            CollapsibleSectionHeader(title: "Ingredients", expanded: $ingredientsExpanded)
                .expandingSectionHeader(RecipeFormSection.ingredients, expanded: ingredientsExpanded)
        } footer: {
            percentageTotal(isExpanded: ingredientsExpanded)
        }
    }

    // MARK: - Shared rows

    /// The foot of an ingredient sheet: a quiet `amberText` action.
    private func addButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                Text(title)
            }
            .fontWeight(.semibold)
            .foregroundStyle(Color.amberText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
    }

    /// The running total of the percentage scale, under the sheet. Plain once it
    /// reaches 100, and then only while the section is open. Short of that it's
    /// a caution, shown even with the section folded so a greyed-out Save always
    /// has its reason on screen: `danger`, saying why, when it blocks Save, and
    /// `warning` for a saved recipe that was already off 100% and is excused
    /// until its rows are edited. Either way it sits as far from the next
    /// section as a sheet does. Shown only in percentage mode, and only once
    /// there is something to total.
    @ViewBuilder
    private func percentageTotal(isExpanded: Bool) -> some View {
        if model.weightUnitIsPercentage && !model.oilDrafts.isEmpty {
            // No-break spaces keep each figure with its "%".
            let rows = model.makesSoap ? String(localized: "Oils") : String(localized: "Ingredients")
            let total = "\(rows) total \(model.totalPercentageText)\u{00A0}%."
            Group {
                if model.percentageTotalBlocksSave {
                    HoneyLedgerFieldNote(
                        "\(total) They must add up to 100\u{00A0}% to save.",
                        tint: .danger,
                        font: .subheadline.weight(.semibold)
                    )
                } else if !model.isPercentageTotalComplete {
                    HoneyLedgerFieldNote("\(total) They should add up to 100\u{00A0}%.", tint: .warning)
                } else if isExpanded {
                    Text("Total \(model.totalPercentageText) %")
                        .font(.footnote)
                        .foregroundStyle(Color.inkSoft)
                }
            }
            .monospacedDigit()
            .padding(.bottom, 16)
        }
    }

    /// A base-ingredient row: the amount redistributes against the other
    /// unlocked base rows to hold the scale at 100%. In percentage mode the
    /// row also shows its weight in the batch, once the lye maths resolves.
    private func baseRow(_ draft: OilIngredientDraft, batchWeight: Double?) -> some View {
        RecipeAmountRow(
            name: draft.ingredient.name,
            amount: Binding(
                get: { draft.amount },
                set: { model.userEdited(id: draft.id, amount: $0) }
            )
        ) {
            HStack(spacing: 10) {
                Text(model.weightUnitIsPercentage ? "%" : model.weightUnit)
                if model.weightUnitIsPercentage, let batchWeight {
                    Text(weightText(batchWeight))
                        .monospacedDigit()
                        .frame(minWidth: weightColumnWidth, alignment: .trailing)
                }
            }
            .foregroundStyle(Color.inkSoft)
        }
    }

    private func weightText(_ weight: Double) -> String {
        "\(weight.formatted(.number.precision(.fractionLength(0...1)))) \(model.displayWeightUnit)"
    }

    // MARK: - Additives

    private var additivesSection: some View {
        Section {
            if additivesExpanded {
                let count = model.additiveDrafts.count + 1
                ForEach(Array(model.additiveDrafts.enumerated()), id: \.element.id) { index, draft in
                    RecipeAmountRow(
                        name: draft.ingredient.name,
                        amount: Binding(
                            get: { draft.amount },
                            set: { model.updateAdditive(id: draft.id, amount: $0) }
                        ),
                        fractionLength: 0...3,
                        fieldWidth: 55
                    ) {
                        additiveUnitMenu(draft)
                    }
                    .ledgerSheetRow(position: .position(index: index, count: count))
                }
                .onDelete(perform: deletingRows(in: .additives, model.removeAdditive))
                .id(deletedRows[.additives, default: 0])
                addButton("Add additive") { activePicker = .additives }
                    .ledgerSheetRow(position: .position(index: count - 1, count: count))
            }
        } header: {
            CollapsibleSectionHeader(title: IngredientCategory.Name.additives, expanded: $additivesExpanded)
                .expandingSectionHeader(RecipeFormSection.additives, expanded: additivesExpanded)
        }
    }

    /// A menu picker rather than a `Menu`: a `Menu` keeps its label at the old
    /// value's width while it closes, so a longer unit showed squeezed ("% c")
    /// for a moment. Tinted `ink`, since the picker draws its value in the
    /// tint and amber is only ever a fill. Laid out at the line's height, so an
    /// additive row is no taller than an oil row.
    private func additiveUnitMenu(_ draft: IngredientAmountDraft) -> some View {
        Picker("Unit", selection: Binding(
            get: { draft.unit },
            set: { model.updateAdditive(id: draft.id, unit: $0) }
        )) {
            ForEach(RecipeUnitOptions.additive, id: \.self) { Text($0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(Color.ink)
        .menuPickerLineHeight()
    }

    // MARK: - Fragrances

    private var fragrancesSection: some View {
        Section {
            if fragrancesExpanded {
                let count = model.fragranceDrafts.count + 2
                RecipeFragrancesHeaderRow(model: model)
                    .ledgerSheetRow(position: .position(index: 0, count: count))
                ForEach(Array(model.fragranceDrafts.enumerated()), id: \.element.id) { index, draft in
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
                            .foregroundStyle(Color.inkSoft)
                    }
                    .ledgerSheetRow(position: .position(index: index + 1, count: count))
                }
                .onDelete(perform: deletingRows(in: .fragrances, model.removeFragrance))
                .id(deletedRows[.fragrances, default: 0])
                addButton("Add fragrance") { activePicker = .fragrances }
                    .ledgerSheetRow(position: .position(index: count - 1, count: count))
            }
        } header: {
            CollapsibleSectionHeader(title: IngredientCategory.Name.fragrances, expanded: $fragrancesExpanded)
                .expandingSectionHeader(RecipeFormSection.fragrances, expanded: fragrancesExpanded)
        } footer: {
            if fragrancesExpanded { blendTotalWarning }
        }
    }

    /// Shown when the blend shares don't add up to 100%. The maths still
    /// resolves — shares are normalised by their actual sum — so this is a
    /// nudge, not an error.
    @ViewBuilder
    private var blendTotalWarning: some View {
        if let blendTotal = model.fragranceBlendTotal, abs(blendTotal - 100) > 0.5 {
            HoneyLedgerFieldNote(
                "Blend shares total \(model.formatPercentage(blendTotal))%. "
                    + "They are applied as shares of that total, not of 100%.",
                tint: .warning
            )
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
