import SwiftUI

/// Adds a product to a batch, or changes one it already has. Writes straight
/// to the batch, like the code and cure edits: what was made is the maker's to
/// correct at any time.
struct BatchProductEditSheet: View {
    let batch: Batch
    /// The product being changed, or `nil` to add one.
    let product: BatchProduct?

    @Environment(\.dismiss) private var dismiss
    @State private var size: Double
    /// Kept as the symbol, not a `ProductUnit`, so a product stored with a unit
    /// this version doesn't know keeps it until the maker picks a known one.
    @State private var unitSymbol: String
    @State private var count: Int?
    /// Set once the count is the maker's own, so a later size or unit change
    /// stops suggesting one over it.
    @State private var countIsTyped: Bool

    /// The recipe's sizes, while the recipe still exists.
    private let quickPicks: [BatchProductSuggestion]
    private let initialSize: Double
    private let initialUnitSymbol: String
    private let initialCount: Int?
    private static let availableUnits = ProductUnit.allCases.filter { $0 != .wholeBatch }

    init(batch: Batch, product: BatchProduct? = nil) {
        self.batch = batch
        self.product = product
        let picks = BatchProductSuggestion.suggestions(from: batch.recipe?.products ?? [])
        quickPicks = picks
        let start = BatchProductSuggestion.newRowStart(
            from: picks,
            oneBatchWeight: batch.oneBatchWeight,
            weightUnit: batch.totalWeightUnit,
            batchCount: batch.batchCount
        )
        let size = product?.size ?? start.size
        let unitSymbol = product?.unitSymbol ?? start.unitSymbol
        let count = product == nil ? start.count : product?.count
        initialSize = size
        initialUnitSymbol = unitSymbol
        initialCount = count
        _size = State(initialValue: size)
        _unitSymbol = State(initialValue: unitSymbol)
        _count = State(initialValue: count)
        _countIsTyped = State(initialValue: product != nil)
    }

    /// `nil` for a symbol this version doesn't know, which is not valid to save.
    private var unit: ProductUnit? { ProductUnit(rawValue: unitSymbol) }

    private var isValid: Bool {
        BatchProduct.isValid(size: size, unitSymbol: unitSymbol, count: count ?? 0)
    }

    private var hasChanges: Bool {
        size != initialSize || unitSymbol != initialUnitSymbol || count != initialCount
    }

    /// What this size makes at the weight the batch was recorded with. Nothing
    /// when no weight was recorded or the size doesn't fit in it.
    private var estimatedCount: Int? {
        BatchProduct.estimatedCount(
            size: size,
            unitSymbol: unitSymbol,
            oneBatchWeight: batch.oneBatchWeight,
            weightUnit: batch.totalWeightUnit,
            batchCount: batch.batchCount
        )
    }

    private var countBinding: Binding<Int?> {
        Binding(
            get: { count },
            set: {
                count = $0
                countIsTyped = true
            }
        )
    }

    private var title: String { product == nil ? "Add Product" : "Edit Product" }

    var body: some View {
        let picks = quickPicks
        let rowCount = picks.isEmpty ? 3 : 4
        let offset = picks.isEmpty ? 0 : 1
        NavigationStack {
            Form {
                Section {
                    if !picks.isEmpty {
                        quickPickMenu(picks)
                            .ledgerSheetRow(position: .position(index: 0, count: rowCount))
                    }
                    HoneyLedgerField("Size") { focus in
                        NumericTextField(
                            prompt: "Size", value: $size, width: 80, fillsAvailableWidth: true,
                            allowsDecimals: unit != .partsOfBatch, focus: focus
                        )
                    }
                    .ledgerSheetRow(position: .position(index: offset, count: rowCount))
                    unitMenu
                        .ledgerSheetRow(position: .position(index: offset + 1, count: rowCount))
                    HoneyLedgerField("Count") { focus in
                        countField(focus)
                    }
                    .ledgerSheetRow(position: .position(index: offset + 2, count: rowCount))
                } footer: {
                    HoneyLedgerFooter("How many of this size the batch made.")
                }
            }
            .environment(\.defaultMinListRowHeight, 48)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle(title)
            .ledgerBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .onChange(of: size) { suggestCount() }
            .onChange(of: unitSymbol) { suggestCount() }
            .interactiveDismissDisabled(hasChanges)
        }
        .fitsSheetToContent()
    }

    private func countField(_ focus: FocusState<Bool>.Binding) -> some View {
        TextField(
            "Count", value: countBinding, format: .number.precision(.fractionLength(0)),
            prompt: Text("Count").foregroundStyle(Color.inkFaint)
        )
        .fontWeight(.medium)
        .monospacedDigit()
        .keyboardType(.numberPad)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: .infinity)
        .focused(focus)
        .tapsAcrossRowHeight { focus.wrappedValue = true }
        .onChange(of: focus.wrappedValue) { _, focused in
            guard focused else { return }
            Task {
                // SwiftUI makes the field first responder after it applies the
                // focus change, so the selection has to wait for that to land.
                await Task.yield()
                guard focus.wrappedValue else { return }
                UIApplication.shared.sendAction(
                    #selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil
                )
            }
        }
    }

    private func quickPickMenu(_ picks: [BatchProductSuggestion]) -> some View {
        Menu {
            ForEach(picks) { pick in
                Button {
                    size = pick.size
                    unitSymbol = pick.unitSymbol
                } label: {
                    MenuSelectionLabel(
                        pick.label,
                        isSelected: size == pick.size && unitSymbol == pick.unitSymbol
                    )
                }
            }
        } label: {
            PickerMenuRowLabel(title: "Recipe size", value: "Choose", isPlaceholder: true)
        }
        .tint(.primary)
    }

    /// A menu rather than a `Picker`: a menu picker draws its value in the
    /// accent colour, and amber is only ever a fill.
    private var unitMenu: some View {
        Menu {
            ForEach(Self.availableUnits, id: \.self) { option in
                Button { select(option) } label: {
                    MenuSelectionLabel(option.label, isSelected: unit == option)
                }
            }
        } label: {
            PickerMenuRowLabel(title: "Unit", value: unit?.label ?? "Choose", isPlaceholder: unit == nil)
        }
        .tint(.primary)
    }

    private func select(_ option: ProductUnit) {
        unitSymbol = option.rawValue
        if option == .partsOfBatch,
           !ProductUnit.isSeparateFromBatch(size: size, unitSymbol: option.rawValue) {
            size = 2
        }
    }

    /// Fills the count of a new product from the batch's weight, unless the
    /// maker has typed their own.
    private func suggestCount() {
        guard product == nil, !countIsTyped else { return }
        count = estimatedCount
    }

    private func save() {
        guard let count else { return }
        let saved = BatchProduct(
            id: product?.id ?? UUID(),
            size: size,
            unitSymbol: unitSymbol,
            count: count
        )
        var products = batch.products
        if let index = products.firstIndex(where: { $0.id == saved.id }) {
            products[index] = saved
        } else {
            products.append(saved)
        }
        batch.products = products
    }
}
