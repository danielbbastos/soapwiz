import SwiftUI

struct BatchDetailView: View {
    let batch: IngredientBatch

    @State private var showingEdit = false

    private var unit: String { batch.ingredient?.unit ?? "" }

    var body: some View {
        List {
            Section("Purchase") {
                LabeledContent("Provider", value: batch.provider?.name ?? "—")
                LabeledContent("Date", value: batch.dateOfPurchase.formatted(date: .long, time: .omitted))
                LabeledContent(
                    "Quantity",
                    value: "\(batch.quantity.formatted(.number.precision(.fractionLength(0...2)))) \(unit)"
                )
                LabeledContent(
                    "Total Price",
                    value: batch.totalPrice.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
                )
                LabeledContent(
                    "Price / \(unit.isEmpty ? "unit" : unit)",
                    value: batch.pricePerUnit.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
                )
            }

            Section("Identification") {
                LabeledContent("Badge", value: batch.badge.isEmpty ? "—" : batch.badge)
                LabeledContent("Journal Code", value: batch.journalCode.isEmpty ? "—" : batch.journalCode)
            }

            Section("Dates") {
                if let expiry = batch.expiryDate {
                    LabeledContent("Expiry Date", value: expiry.formatted(date: .long, time: .omitted))
                }
                if let opening = batch.openingDate {
                    LabeledContent("Opening Date", value: opening.formatted(date: .long, time: .omitted))
                }
                if batch.expiryDate == nil && batch.openingDate == nil {
                    Text("No dates recorded")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Stock") {
                LabeledContent("Remaining") {
                    Text("\(batch.remainingAmount.formatted(.number.precision(.fractionLength(0...2)))) \(unit)")
                        .foregroundStyle(batch.remainingAmount > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.red))
                }
                LabeledContent("Storage Location", value: batch.storageLocation?.name ?? "—")
            }
        }
        .navigationTitle("Batch Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let ingredient = batch.ingredient {
                BatchFormView(ingredient: ingredient, batch: batch)
            }
        }
    }
}
