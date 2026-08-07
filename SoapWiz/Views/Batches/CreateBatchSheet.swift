import SwiftUI
import SwiftData

/// Prompts for how many batches to make and creates one. Insufficient stock is
/// surfaced inline — the affected ingredients and shortfalls are listed and
/// creation is blocked until the count is reduced or stock is replenished.
struct CreateBatchSheet: View {
    let recipe: Recipe
    let lyeCandidates: [Ingredient]
    /// Called with the created batch so the caller can navigate to it.
    let onCreated: (Batch) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model: BatchProductionViewModel

    init(recipe: Recipe, lyeCandidates: [Ingredient], onCreated: @escaping (Batch) -> Void) {
        self.recipe = recipe
        self.lyeCandidates = lyeCandidates
        self.onCreated = onCreated
        _model = State(initialValue: BatchProductionViewModel(recipe: recipe, lyeCandidates: lyeCandidates))
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()

    private func amountText(_ amount: Double, unit: String) -> String {
        "\(amount.formatted(.number.precision(.fractionLength(0...2)))) \(unit)"
    }

    var body: some View {
        NavigationStack {
            Form {
                let requirements = model.requirements
                let shortages = requirements.filter(\.isShort)
                let estimatedCost = model.estimatedCost
                let totalBatchWeight = model.totalBatchWeight

                Section {
                    Stepper(value: $model.batchCount, in: 1...999) {
                        LabeledContent("Batches", value: "\(model.batchCount)")
                    }
                    // Shown even when stock is short, unlike estimated cost: the
                    // size of the batch you can't yet make is what tells you how
                    // much more to buy.
                    if totalBatchWeight > 0 {
                        LabeledContent(
                            "Total weight",
                            value: amountText(totalBatchWeight, unit: model.batchWeightUnit)
                        )
                    }
                    if shortages.isEmpty && estimatedCost > 0 {
                        LabeledContent(
                            "Estimated cost",
                            value: Self.currencyFormatter.string(from: NSNumber(value: estimatedCost)) ?? "—"
                        )
                    }
                }
                .listRowBackground(Color.cardBackground)

                if requirements.isEmpty {
                    Section {
                        Text("This recipe has no ingredients to consume.")
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.cardBackground)
                } else if !shortages.isEmpty {
                    Section("Not enough stock") {
                        ForEach(shortages) { req in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(req.ingredient.name)
                                Text("Need \(amountText(req.required, unit: req.unit)), have \(amountText(req.available, unit: req.unit))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listRowBackground(Color.cardBackground)
                }
            }
            .navigationTitle("Create Batch")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle("Create Batch")
            .warmBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        if let batch = model.create(context: context) {
                            dismiss()
                            onCreated(batch)
                        }
                    }
                    .disabled(!model.canCreate)
                }
            }
        }
    }
}
