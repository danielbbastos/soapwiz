import SwiftUI
import SwiftData

/// Shows what planning a batch adds to the shopping list, and adds it on
/// confirmation. Pushed from Create Batch, which it closes once added.
struct PlanBatchConfirmationView: View {
    @Environment(\.modelContext) private var modelContext

    // Queried here rather than passed in: they are read only while this screen is open.
    @Query(sort: \ShoppingListItem.createdAt) private var items: [ShoppingListItem]
    @Query private var purchases: [IngredientPurchase]

    let shortages: [BatchRequirement]
    let recipeName: String
    let batchCount: Int
    let onAdded: () -> Void

    private func amountText(_ amount: Double, unit: String) -> String {
        "\(amount.formatted(.number.precision(.fractionLength(0...2)))) \(unit)"
    }

    var body: some View {
        let boughtDates = ShoppingListBought.dates(items: items, purchases: purchases)
        let lines = ShoppingListBatchPlan.lines(
            shortages: shortages,
            recipeName: recipeName,
            batchCount: batchCount,
            items: items,
            boughtDates: boughtDates
        )
        Form {
            Section {
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    HoneyLedgerLabeledRow(line.ingredient.name, value: {
                        Text.honeyLedgerFigure(amountText(line.amount, unit: line.unit))
                    }, below: {
                        if line.mergeTarget != nil {
                            Text("Adds to an item already on the list")
                                .font(.footnote)
                                .foregroundStyle(Color.inkSoft)
                        }
                    })
                    .ledgerSheetRow(position: .position(index: index, count: lines.count))
                }
            } header: {
                HoneyLedgerSectionLabel("To add")
            } footer: {
                HoneyLedgerFooter(
                    "These are what \(recipeName) \u{00D7}\(batchCount) is short of."
                )
            }
        }
        .navigationTitle("Add to shopping list")
        .navigationBarTitleDisplayMode(.inline)
        .honeyLedgerInlineTitle("Add to shopping list")
        .ledgerBackground()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    ShoppingListViewModel(modelContext: modelContext).addPlanned(lines)
                    onAdded()
                }
                .disabled(lines.isEmpty)
            }
        }
    }
}
