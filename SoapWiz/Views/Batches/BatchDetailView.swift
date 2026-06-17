import SwiftUI

/// Read-only view of the immutable snapshot a `Batch` recorded at creation:
/// what was consumed, which purchases it drew from, and what it cost. Nothing
/// here recomputes against the live recipe or inventory.
struct BatchDetailView: View {
    let batch: Batch

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()

    private func formatCurrency(_ value: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: value)) ?? "—"
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
                LabeledContent("Total cost", value: formatCurrency(batch.totalCost))
                if batch.batchCount > 1 {
                    LabeledContent("Cost per batch", value: formatCurrency(BatchHistoryViewModel.costPerBatch(of: batch)))
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
