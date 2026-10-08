import SwiftUI

/// Adds a product size to a recipe's cost breakdown — "what would 100 g bars
/// cost?" — without opening the recipe form. Hands the finished draft back to
/// the caller, which owns persisting it.
struct AddRecipeProductSheet: View {
    let onAdd: (RecipeProductDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = RecipeProductDraft(size: Self.initialSize, unitSymbol: Self.initialUnit)

    private static let initialSize: Double = 100
    private static let initialUnit = ProductUnit.grams.rawValue

    /// Whether the size or unit was changed, which stops a swipe from closing
    /// the sheet.
    private var hasChanges: Bool {
        draft.size != Self.initialSize || draft.unitSymbol != Self.initialUnit
    }

    private var unit: ProductUnit { ProductUnit(rawValue: draft.unitSymbol) ?? .grams }

    /// Routed through the draft so a unit change adjusts the size by the same
    /// rule as the form's cards.
    private var unitSelection: Binding<ProductUnit> {
        Binding(get: { unit }, set: { draft.selectUnit($0) })
    }

    /// The whole batch already has its own row in the breakdown, so offering it
    /// here would add a product that never appears.
    private static let availableUnits = ProductUnit.allCases.filter { $0 != .wholeBatch }

    /// A single part is the whole batch under another name, and is filtered out
    /// of the breakdown for that reason. Parts come in whole numbers.
    private var isValid: Bool {
        draft.isSeparateFromBatch && draft.size > 0
    }

    private var footerText: String {
        if unit == .partsOfBatch {
            return "The batch split into equal parts — a size of 4 costs one quarter of it."
        }
        return "One product of this size, costed from its share of the batch."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HoneyLedgerField("Size") { focus in
                        NumericTextField(
                            prompt: "Size", value: $draft.size, width: 80, fillsAvailableWidth: true,
                            allowsDecimals: unit != .partsOfBatch, focus: focus
                        )
                    }
                    .ledgerSheetRow(position: .first)
                    unitMenu
                        .ledgerSheetRow(position: .last)
                } footer: {
                    Text(footerText)
                        .font(.footnote)
                        .foregroundStyle(Color.inkSoft)
                }
            }
            .environment(\.defaultMinListRowHeight, 48)
            .navigationTitle("Add Size")
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle("Add Size")
            .ledgerBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(draft)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .interactiveDismissDisabled(hasChanges)
        }
    }

    /// A menu rather than a `Picker`: a menu picker draws its value in the
    /// accent colour, and amber is only ever a fill.
    private var unitMenu: some View {
        Menu {
            ForEach(Self.availableUnits, id: \.self) { option in
                Button { unitSelection.wrappedValue = option } label: {
                    MenuSelectionLabel(option.label, isSelected: unit == option)
                }
            }
        } label: {
            PickerMenuRowLabel(title: "Unit", value: unit.label)
        }
        .tint(.primary)
    }
}
