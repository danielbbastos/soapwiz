import SwiftUI
import SwiftData

/// The "Cost breakdown" section of a recipe's detail screen: the whole-batch
/// total with RRP, plus an expandable per-product cost breakdown. Reads its
/// figures from the view model and the app's RRP factor from settings, and
/// writes back only the recipe's products, which can be added and deleted here.
struct RecipeCostSection: View {
    let model: RecipeFormViewModel
    let batch: ProductCostBreakdown

    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettings]
    @State private var batchTotalExpanded = false
    @State private var expandedProducts: [UUID: Bool] = [:]
    @State private var showingAddProduct = false
    @State private var showingSaveError = false

    private static let currencyFormatter: NumberFormatter = {
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

    private var pvpFactor: Double { AppSettings.canonical(from: settingsRecords)?.pvpFactor ?? 4.0 }

    var body: some View {
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
                .expandingSectionHeader(
                    RecipeFormSection.batchTotal,
                    expanded: batchTotalExpanded,
                    spansWholeSection: true
                )
            } else {
                Text("No cost data — add purchase prices in Inventory")
                    .foregroundStyle(.secondary)
            }

            let products = nonWholeBatchProducts
            let breakdowns = productBreakdowns(products, batch: batch)
            ForEach(products, id: \.id) { draft in
                let breakdown = breakdowns[draft.id] ?? ProductCostBreakdown()
                // Without costs there is nothing to disclose, but the product is
                // still listed — it was just added, and hiding it would read as
                // the add having failed.
                if breakdown.total > 0 {
                    DisclosureGroup(isExpanded: isExpanded(draft)) {
                        productBreakdownRows(breakdown)
                    } label: {
                        productDisclosureLabel(draft, breakdown: breakdown)
                    }
                    .expandingSectionHeader(
                        RecipeFormSection.product(draft.id),
                        expanded: expandedProducts[draft.id] ?? false,
                        spansWholeSection: true
                    )
                } else {
                    productDisclosureLabel(draft, breakdown: breakdown)
                }
            }
            .onDelete(perform: deleteProducts)

            // The sheet hangs off the button rather than the section: a
            // modifier on a `Section` is applied to each of its rows, which
            // leaves several presentations bound to one flag and none of them
            // showing.
            Button {
                showingAddProduct = true
            } label: {
                Label("Add product", systemImage: "plus.circle.fill")
            }
            .sheet(isPresented: $showingAddProduct) {
                AddRecipeProductSheet { draft in
                    saveProducts { model.productDrafts.append(draft) }
                }
            }
            .alert("Couldn't save products", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The change was not saved. Please try again.")
            }
        }
        .listRowBackground(Color.cardBackground)
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
        model.productDrafts.filter { draft in
            let unit = ProductUnit(rawValue: draft.unitSymbol)
            if unit == .wholeBatch { return false }
            if unit == .partsOfBatch && draft.size <= 1 { return false }
            return true
        }
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
            get: { expandedProducts[draft.id] ?? false },
            set: { expandedProducts[draft.id] = $0 }
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

    private func amountText(_ amount: Double, unit: String) -> String {
        let formatted = amount.formatted(.number.precision(.fractionLength(0...2)))
        return "\(formatted) \(unit)"
    }

    private func productDisclosureLabel(_ draft: RecipeProductDraft, breakdown: ProductCostBreakdown) -> some View {
        HStack {
            Text(productLabel(draft))
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(breakdown.total > 0 ? formatCurrency(breakdown.total) : "—")
                    .font(.subheadline)
                    .foregroundStyle(breakdown.total > 0 ? .primary : .secondary)
                    .monospacedDigit()
                if breakdown.total > 0 {
                    Text("RRP \(formatCurrency(breakdown.total * pvpFactor))")
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .monospacedDigit()
                }
            }
        }
    }

    private func productBreakdownRows(_ breakdown: ProductCostBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(BreakdownGroupKey.groups(of: breakdown), id: \.key) { group in
                Text(group.key.displayName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                ForEach(group.rows, id: \.ingredient.persistentModelID) { row in
                    let display = model.displayedAmount(for: row, usesEnteredUnit: group.key.usesEnteredUnit)
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
