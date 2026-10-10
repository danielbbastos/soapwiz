import SwiftUI
import SwiftData

/// The "Cost breakdown" section of a recipe's detail screen: one sheet with the
/// whole batch's cost and RRP, then each product size the user tries out, then
/// "Add size". Each costed row opens in place onto its per-ingredient lines.
/// The whole batch is flagged when some ingredients have no price, and a "No
/// cost data" note stands in for it when none has one. Reads its figures from
/// the view model and the app's RRP factor from settings, and writes back only
/// the recipe's products, which can be added and deleted here.
///
/// Hidden with inventory tracking off: without prices there is nothing to
/// calculate. The sizes stay stored and come back when tracking is switched on.
struct RecipeCostSection: View {
    @Environment(\.currencyCode) private var currencyCode
    let model: RecipeFormViewModel
    let batch: ProductCostBreakdown

    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettings]
    @State private var batchTotalExpanded = false
    @State private var expandedProducts: Set<UUID> = []
    @State private var showingAddProduct = false
    @State private var showingSaveError = false

    private static let amountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private var pvpFactor: Double { AppSettings.canonical(from: settingsRecords)?.pvpFactor ?? 4.0 }
    private var tracksInventory: Bool { AppSettings.tracksInventory(from: settingsRecords) }

    var body: some View {
        if tracksInventory {
            calculatorSection
        }
    }

    private var calculatorSection: some View {
        let products = nonWholeBatchProducts
        let breakdowns = productBreakdowns(products, batch: batch)
        let rowCount = products.count + 2
        return Section {
            Group {
                if batch.total > 0 {
                    costRow(
                        title: ProductUnit.wholeBatch.label,
                        caption: wholeBatchCaption,
                        breakdown: batch,
                        isExpanded: $batchTotalExpanded
                    ) {
                        unpricedWarning
                    }
                } else {
                    Text("No cost data — add purchase prices in Inventory")
                        .foregroundStyle(Color.inkSoft)
                }
            }
            .ledgerSheetRow(position: .position(index: 0, count: rowCount))

            ForEach(Array(products.enumerated()), id: \.element.id) { index, draft in
                let breakdown = breakdowns[draft.id] ?? ProductCostBreakdown()
                costRow(
                    title: productLabel(draft),
                    caption: productCaption(breakdown),
                    breakdown: breakdown,
                    isExpanded: isExpanded(draft)
                ) {
                    EmptyView()
                }
                .ledgerSheetRow(position: .position(index: index + 1, count: rowCount))
            }
            .onDelete(perform: deleteProducts)

            // The sheet hangs off the button rather than the section: a
            // modifier on a `Section` is applied to each of its rows, which
            // leaves several presentations bound to one flag and none of them
            // showing.
            Button {
                showingAddProduct = true
            } label: {
                Label("Add size", systemImage: "plus.circle")
                    .foregroundStyle(Color.amberText)
            }
            .ledgerSheetRow(position: .position(index: rowCount - 1, count: rowCount))
            .sheet(isPresented: $showingAddProduct) {
                AddRecipeProductSheet { draft in
                    saveProducts { model.productDrafts.append(draft) }
                }
            }
            .alert("Couldn't save sizes", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The change was not saved. Please try again.")
            }
        } header: {
            HoneyLedgerSectionLabel("Cost breakdown")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if batch.total > 0, batch.unpricedIngredientCount > 0 {
                    Text("Add purchase prices in Inventory to include every ingredient.")
                }
                Text("Try product sizes, like one bar or a quarter of the batch, to see what each would cost. "
                    + "They don't affect batches or inventory.")
            }
            .font(.footnote)
            .foregroundStyle(Color.inkSoft)
        }
    }

    private func deleteProducts(at offsets: IndexSet) {
        // The offsets index the filtered list the rows were built from, which is
        // derived rather than the source of truth — so they are matched against
        // a freshly computed copy rather than subscripted blindly.
        let products = nonWholeBatchProducts
        let deletedIDs = Set(offsets.compactMap { products.indices.contains($0) ? products[$0].id : nil })
        guard !deletedIDs.isEmpty else { return }
        saveProducts { model.productDrafts.removeAll { deletedIDs.contains($0.id) } }
    }

    /// Applies a draft mutation and persists it. On a failed save the drafts
    /// are restored, so the rows never show a change the store didn't take,
    /// and the failure is surfaced in an alert.
    private func saveProducts(after change: () -> Void) {
        let previousDrafts = model.productDrafts
        change()
        do {
            try model.saveProducts(context: modelContext)
        } catch {
            model.productDrafts = previousDrafts
            showingSaveError = true
        }
    }

    private var nonWholeBatchProducts: [RecipeProductDraft] {
        model.productDrafts.filter(\.isSeparateFromBatch)
    }

    private func productBreakdowns(
        _ products: [RecipeProductDraft], batch: ProductCostBreakdown
    ) -> [UUID: ProductCostBreakdown] {
        Dictionary(uniqueKeysWithValues: products.map { draft in
            (draft.id, model.breakdownAndCost(for: draft, batch: batch))
        })
    }

    private func isExpanded(_ draft: RecipeProductDraft) -> Binding<Bool> {
        Binding(
            get: { expandedProducts.contains(draft.id) },
            set: { isOn in
                if isOn {
                    expandedProducts.insert(draft.id)
                } else {
                    expandedProducts.remove(draft.id)
                }
            }
        )
    }

    // MARK: - Labels

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

    /// The batch's own scale: its oils for a soap, which is what the recipe is
    /// written against, or its whole weight for anything else.
    private var wholeBatchCaption: String? {
        if model.makesSoap {
            let oils = (model.oilAmountCalculations ?? []).reduce(0) { $0 + $1.weight }
            guard oils > 0 else { return nil }
            return "\(amountText(oils, unit: model.displayWeightUnit)) oils"
        }
        guard let total = model.calculatedAmountRows?.last(where: \.isSummary)?.weight, total > 0 else { return nil }
        return amountText(total, unit: model.displayWeightUnit)
    }

    /// How many of the size one batch makes. A part of the batch already says
    /// so in its name, so it has no caption.
    private func productCaption(_ breakdown: ProductCostBreakdown) -> String? {
        if breakdown.exceedsBatchWeight {
            return "Larger than the batch"
        }
        return breakdown.sizesPerBatch.map(CostBreakdownCaption.sizesPerBatch)
    }

    @ViewBuilder
    private var unpricedWarning: some View {
        let unpriced = batch.unpricedIngredientCount
        if unpriced > 0 {
            HoneyLedgerFieldNote(
                unpriced == 1 ? "1 ingredient has no price" : "\(unpriced) ingredients have no price",
                tint: .warning
            )
            .padding(.top, 4)
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        value.formatted(.currency(code: currencyCode))
    }

    private func amountText(_ amount: Double, unit: String) -> String {
        let formatted = amount.formatted(.number.precision(.fractionLength(0...2)))
        return "\(formatted) \(unit)"
    }

    // MARK: - Rows

    /// A top-level row of the sheet: the name with its caption, the total with
    /// its RRP, and a chevron that opens the ingredient lines underneath, inside
    /// the same row. A size nothing in it is priced for shows a dash and
    /// doesn't open.
    private func costRow<Warning: View>(
        title: String,
        caption: String?,
        breakdown: ProductCostBreakdown,
        isExpanded: Binding<Bool>,
        @ViewBuilder warning: () -> Warning
    ) -> some View {
        let isCosted = breakdown.total > 0
        return VStack(alignment: .leading, spacing: 0) {
            // Not `.disabled` for an uncosted row, which would dim its name too.
            Button {
                guard isCosted else { return }
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.wrappedValue.toggle() }
            } label: {
                costRowHead(title: title, caption: caption, breakdown: breakdown, isExpanded: isExpanded.wrappedValue) {
                    warning()
                }
            }
            .buttonStyle(.plain)
            .accessibilityValue(expansionState(isCosted: isCosted, isExpanded: isExpanded.wrappedValue))

            if isCosted, isExpanded.wrappedValue {
                breakdownLines(breakdown)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
            }
        }
    }

    private func expansionState(isCosted: Bool, isExpanded: Bool) -> String {
        guard isCosted else { return "" }
        return isExpanded ? String(localized: "Expanded") : String(localized: "Collapsed")
    }

    private func costRowHead<Warning: View>(
        title: String,
        caption: String?,
        breakdown: ProductCostBreakdown,
        isExpanded: Bool,
        @ViewBuilder warning: () -> Warning
    ) -> some View {
        let isCosted = breakdown.total > 0
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ink)
                if let caption {
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(Color.inkSoft)
                }
                warning()
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(isCosted ? formatCurrency(breakdown.total) : "—")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isCosted ? Color.ink : Color.inkSoft)
                if isCosted {
                    Text("RRP \(formatCurrency(breakdown.total * pvpFactor))")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Color.amberText)
                }
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.inkFaint)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .opacity(isCosted ? 1 : 0)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
    }

    /// The ingredient lines under an open row: grouped under small headings,
    /// each a name, an amount in `inkSoft` and a cost in `ink`, in three
    /// aligned columns, with space rather than dividers between the groups.
    private func breakdownLines(_ breakdown: ProductCostBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(BreakdownGroupKey.groups(of: breakdown), id: \.key) { group in
                Text(group.key.displayName)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.9)
                    .foregroundStyle(Color.inkSoft)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                ForEach(group.rows, id: \.ingredient.persistentModelID) { row in
                    breakdownLine(row, usesEnteredUnit: group.key.usesEnteredUnit)
                }
            }
        }
    }

    private func breakdownLine(_ row: IngredientProductBreakdown, usesEnteredUnit: Bool) -> some View {
        let display = model.displayedAmount(for: row, usesEnteredUnit: usesEnteredUnit)
        return HStack(spacing: 8) {
            Text(row.ingredient.name)
                .foregroundStyle(Color.ink)
            Spacer(minLength: 4)
            if let note = display.conversionNote {
                InfoPopoverIcon(text: note)
            }
            Text(amountText(display.amount, unit: display.unit))
                .foregroundStyle(Color.inkSoft)
            // Always render the cost cell, with a dash when the ingredient has
            // no price, so the amount stays in its own column instead of
            // sliding into the cost's.
            Text(row.cost > 0 ? formatCurrency(row.cost) : "—")
                .foregroundStyle(row.cost > 0 ? Color.ink : Color.inkSoft)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .font(.subheadline)
        .monospacedDigit()
        .padding(.vertical, 3)
    }
}
