import SwiftUI

/// Read-only view of the immutable snapshot a `Batch` recorded at creation:
/// what was consumed, which purchases it drew from, and what it cost. Nothing
/// here recomputes against the live recipe or inventory — including whether
/// the batch was costed at all, which is the snapshot's `tracksInventory`.
struct BatchDetailView: View {
    @Environment(\.currencyCode) private var currencyCode
    let batch: Batch

    private func formatCurrency(_ value: Double) -> String {
        value.formatted(.currency(code: currencyCode))
    }

    private func amountText(_ amount: Double, unit: String) -> String {
        "\(amount.formatted(.number.precision(.fractionLength(0...2)))) \(unit)"
    }

    private var sortedLineItems: [BatchLineItem] {
        BatchHistoryViewModel.sortedLineItems(of: batch)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Recipe", value: batch.recipeName)
                LabeledContent("Date", value: batch.dateCreated.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Batches", value: "\(batch.batchCount)")
                if batch.tracksInventory {
                    LabeledContent("Total cost", value: formatCurrency(batch.totalCost))
                    if batch.batchCount > 1, let costPerBatch = BatchHistoryViewModel.costPerBatch(of: batch) {
                        LabeledContent("Cost per batch", value: formatCurrency(costPerBatch))
                    }
                }
            } footer: {
                if !batch.tracksInventory {
                    Text("Made without inventory tracking, so no cost was recorded.")
                }
            }
            .listRowBackground(Color.cardBackground)

            Section("Consumed") {
                ForEach(sortedLineItems) { item in
                    lineItemRow(item)
                }
            }
            .listRowBackground(Color.cardBackground)

            Section {
                if let recipe = batch.recipe {
                    NavigationLink(value: recipe) {
                        Label("Open recipe", systemImage: "function")
                    }
                } else {
                    Label("The original recipe no longer exists.", systemImage: "function")
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.cardBackground)
        }
        .navigationTitle("Batch")
        .navigationBarTitleDisplayMode(.inline)
        .warmNavigationTitle("Batch")
        .warmBackground()
    }

    private func lineItemRow(_ item: BatchLineItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.ingredientName)
                Spacer()
                Text(amountText(item.amountConsumed, unit: item.unit))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if item.cost > 0 {
                    Text(formatCurrency(item.cost))
                        .monospacedDigit()
                        .frame(width: 72, alignment: .trailing)
                }
            }
            ForEach(item.draws.indices, id: \.self) { index in
                let draw = item.draws[index]
                HStack {
                    Text(draw.purchaseBadge.isEmpty ? "No lot" : "Lot \(draw.purchaseBadge)")
                    Spacer()
                    Text("\(amountText(draw.amountDrawn, unit: item.unit)) @ \(formatCurrency(draw.pricePerUnit))/\(item.unit)")
                        .monospacedDigit()
                    Text(formatCurrency(draw.cost))
                        .monospacedDigit()
                        .frame(width: 72, alignment: .trailing)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }
}
