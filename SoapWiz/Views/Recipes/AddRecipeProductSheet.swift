import SwiftUI

/// Adds a product size to a recipe's cost breakdown — "what would 100 g bars
/// cost?" — without opening the recipe form. Hands the finished draft back to
/// the caller, which owns persisting it.
struct AddRecipeProductSheet: View {
    let onAdd: (RecipeProductDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var size: Double = 100
    @State private var unit: ProductUnit = .grams

    /// The whole batch already has its own row in the breakdown, so offering it
    /// here would add a product that never appears.
    private static let availableUnits = ProductUnit.allCases.filter { $0 != .wholeBatch }

    /// A single part is the whole batch under another name, and is filtered out
    /// of the breakdown for that reason.
    private var isValid: Bool {
        unit == .partsOfBatch ? size > 1 : size > 0
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
                    LabeledContent("Size") {
                        NumericTextField(prompt: "Size", value: $size, width: 80)
                    }
                    Picker("Unit", selection: $unit) {
                        ForEach(Self.availableUnits, id: \.self) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                } footer: {
                    Text(footerText)
                }
                .listRowBackground(Color.cardBackground)
            }
            .navigationTitle("Add Product")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle("Add Product")
            .warmBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(RecipeProductDraft(size: size, unitSymbol: unit.rawValue))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
