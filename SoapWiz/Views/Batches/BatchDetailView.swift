import SwiftUI

/// Minimal batch detail. The full history-tab and detail experience is built in
/// SW-75; this lands just enough to confirm a batch was created and show what it
/// consumed and cost.
struct BatchDetailView: View {
    let batch: Batch

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .autoupdatingCurrent
        return f
    }()

    private func formatCurrency(_ value: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: value)) ?? "—"
    }

    private func amountText(_ amount: Double, unit: String) -> String {
        "\(amount.formatted(.number.precision(.fractionLength(0...2)))) \(unit)"
    }

    private var sortedLineItems: [BatchLineItem] {
        batch.lineItems.sorted { $0.ingredientName < $1.ingredientName }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Recipe", value: batch.recipeName)
                LabeledContent("Date", value: batch.dateCreated.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Batches", value: "\(batch.batchCount)")
                LabeledContent("Total cost", value: formatCurrency(batch.totalCost))
            }

            Section("Consumed") {
                ForEach(sortedLineItems) { item in
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
                }
            }
        }
        .navigationTitle("Batch")
        .navigationBarTitleDisplayMode(.inline)
    }
}
