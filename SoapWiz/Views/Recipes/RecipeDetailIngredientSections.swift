import SwiftUI
import SwiftData

/// The recipe detail's ingredient sheets: Oils and Additives for a soap, one
/// merged Ingredients sheet otherwise, then Fragrances and Calculated amounts.
/// Emits `Section`s, so it must sit directly inside a `List`.
struct RecipeDetailIngredientSections: View {
    let model: RecipeFormViewModel
    let batch: ProductCostBreakdown
    @Binding var showInGrams: Bool

    /// The unit the weights are shown in: the recipe's oil weight unit, or
    /// grams when the user toggles it.
    private var displayUnit: String { showInGrams ? "g" : model.displayWeightUnit }

    /// Offer the grams toggle only when the recipe isn't already measured in grams.
    private var showsUnitToggle: Bool { model.displayWeightUnit != "g" }

    var body: some View {
        if model.makesSoap {
            oilsSection
            additivesSection
        } else {
            ingredientsSection
        }
        fragrancesSection
        calculatedAmountsSection
    }

    // MARK: - Ingredients

    private var sortedOils: [OilIngredientDraft] {
        model.oilDrafts.sorted { $0.amount > $1.amount }
    }

    private var oilBatchWeightByDraftId: [UUID: Double] {
        Dictionary(uniqueKeysWithValues: (model.oilAmountCalculations ?? []).map { ($0.id, $0.weight) })
    }

    private var oilsSection: some View {
        let oils = sortedOils
        let weights = oilBatchWeightByDraftId
        return Section {
            if oils.isEmpty {
                emptyRow("No oils added")
            } else {
                ForEach(Array(oils.enumerated()), id: \.element.id) { index, draft in
                    amountRow(draft.ingredient.name, oilAmount(draft, batchWeight: weights[draft.id]))
                        .ledgerSheetRow(position: .position(index: index, count: oils.count))
                }
            }
        } header: {
            HoneyLedgerSectionLabel("Oils")
        }
    }

    /// The merged section a non-soap recipe shows in place of Oils and
    /// Additives, mirroring the form's Ingredients tab — the same recipe should
    /// not be split one way on the edit screen and another way here.
    private var ingredientsSection: some View {
        let oils = sortedOils
        let oilWeights = oilBatchWeightByDraftId
        let additiveWeights = batchWeightLookup(batch.additives)
        let count = oils.count + model.additiveDrafts.count
        return Section {
            if count == 0 {
                emptyRow("No ingredients added")
            } else {
                ForEach(Array(oils.enumerated()), id: \.element.id) { index, draft in
                    amountRow(draft.ingredient.name, oilAmount(draft, batchWeight: oilWeights[draft.id]))
                        .ledgerSheetRow(position: .position(index: index, count: count))
                }
                ForEach(Array(model.additiveDrafts.enumerated()), id: \.element.id) { index, draft in
                    let weight = additiveWeights[draft.ingredient.persistentModelID]
                    amountRow(draft.ingredient.name, ingredientAmount(draft, batchWeight: weight))
                        .ledgerSheetRow(position: .position(index: oils.count + index, count: count))
                }
            }
        } header: {
            HoneyLedgerSectionLabel("Ingredients")
        }
    }

    @ViewBuilder
    private var additivesSection: some View {
        if !model.additiveDrafts.isEmpty {
            ingredientSheet("Additives", drafts: model.additiveDrafts, rows: batch.additives)
        }
    }

    @ViewBuilder
    private var fragrancesSection: some View {
        if !model.fragranceDrafts.isEmpty {
            ingredientSheet("Fragrances", drafts: model.fragranceDrafts, rows: batch.fragrances)
        }
    }

    private func ingredientSheet(
        _ title: String,
        drafts: [IngredientAmountDraft],
        rows: [IngredientProductBreakdown]
    ) -> some View {
        let weights = batchWeightLookup(rows)
        return Section {
            ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                let weight = weights[draft.ingredient.persistentModelID]
                amountRow(draft.ingredient.name, ingredientAmount(draft, batchWeight: weight))
                    .ledgerSheetRow(position: .position(index: index, count: drafts.count))
            }
        } header: {
            HoneyLedgerSectionLabel(title)
        }
    }

    /// Maps each breakdown row's ingredient to its amount in the oil weight unit.
    /// Amounts are summed rather than assumed unique — a recipe that ends up with
    /// two rows for one ingredient should render, not trap.
    private func batchWeightLookup(_ rows: [IngredientProductBreakdown]) -> [PersistentIdentifier: Double] {
        Dictionary(rows.map { ($0.ingredient.persistentModelID, $0.ingredientAmount) }, uniquingKeysWith: +)
    }

    // MARK: - Amounts

    /// Converts an amount expressed in the oil weight unit into the chosen display unit.
    private func displayed(_ batchAmount: Double) -> Double {
        MassUnitConverter.convert(batchAmount, from: model.displayWeightUnit, to: displayUnit) ?? batchAmount
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func weightText(_ batchAmount: Double) -> String {
        "\(formatted(displayed(batchAmount))) \(displayUnit)"
    }

    private func weightAmount(_ batchAmount: Double) -> LedgerAmountText {
        LedgerAmountText(number: formatted(displayed(batchAmount)), unit: displayUnit)
    }

    private func oilAmount(_ draft: OilIngredientDraft, batchWeight: Double?) -> LedgerAmountText {
        if model.weightUnitIsPercentage {
            return LedgerAmountText(
                number: model.formatPercentage(draft.amount),
                unit: "%",
                convertedWeight: batchWeight.map(weightText)
            )
        }
        // Absolute mode: the entered amount is already in the oil weight unit.
        return weightAmount(batchWeight ?? draft.amount)
    }

    /// Adds the converted weight only when the ingredient is expressed as a
    /// percentage; absolute units (g, kg, ml, …) stand alone.
    private func ingredientAmount(_ draft: IngredientAmountDraft, batchWeight: Double?) -> LedgerAmountText {
        let showsWeight = RecipeUnitOptions.isPercentage(draft.unit) && (batchWeight ?? 0) > 0
        return LedgerAmountText(
            number: formatted(draft.amount),
            unit: model.unitLabel(for: draft.unit),
            convertedWeight: showsWeight ? batchWeight.map(weightText) : nil
        )
    }

    private func amountRow(_ name: String, _ amount: LedgerAmountText) -> some View {
        HoneyLedgerLabeledRow(name) {
            Text.ledgerAmount(amount, figureWeight: .semibold)
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Color.inkSoft)
            .ledgerSheetRow(position: .only)
    }

    // MARK: - Calculated amounts

    @ViewBuilder
    private var calculatedAmountsSection: some View {
        Section {
            if let rows = model.calculatedAmountRows {
                let offset = showsUnitToggle ? 1 : 0
                let count = rows.count + offset
                if showsUnitToggle {
                    Picker("Units", selection: $showInGrams) {
                        Text(model.displayWeightUnit).tag(false)
                        Text("g").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .ledgerSheetRow(position: .position(index: 0, count: count))
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    // A total sits under a hairline in `inkSoft` rather than the
                    // pale `rule`. That hairline is shared with the row above, so
                    // both rows tint it.
                    let precedesTotal = rows.indices.contains(index + 1) && rows[index + 1].isSummary
                    // Inside `ledgerSheetRow`, whose own `rule` tint would
                    // otherwise win.
                    calculatedRow(row)
                        .listRowSeparatorTint(row.isSummary ? Color.inkSoft : Color.rule, edges: .top)
                        .listRowSeparatorTint(precedesTotal ? Color.inkSoft : Color.rule, edges: .bottom)
                        .ledgerSheetRow(position: .position(index: index + offset, count: count))
                }
            } else {
                emptyRow("Add oils to see calculated amounts")
            }
        } header: {
            HoneyLedgerSectionLabel("Calculated amounts")
        }
    }

    /// A total is set semibold; its darker hairline is tinted by the caller.
    private func calculatedRow(_ row: CalculatedAmountRow) -> some View {
        HoneyLedgerLabeledRow(row.label) {
            Text.ledgerAmount(weightAmount(row.weight), figureWeight: row.isSummary ? .semibold : .medium)
        } below: {
            if let note = row.note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Color.inkSoft)
            }
        }
        .fontWeight(row.isSummary ? .semibold : nil)
    }
}

extension Text {
    /// A `LedgerAmountText` in the body size with monospaced digits: the figure
    /// in `ink` at `figureWeight`, its detail in `inkSoft`.
    static func ledgerAmount(_ amount: LedgerAmountText, figureWeight: Font.Weight = .medium) -> Text {
        let figure = Text(amount.figure)
            .fontWeight(figureWeight)
            .foregroundStyle(Color.ink)
        let detail = Text(amount.detail)
            .foregroundStyle(Color.inkSoft)
        return (figure + detail).font(.body).monospacedDigit()
    }
}
