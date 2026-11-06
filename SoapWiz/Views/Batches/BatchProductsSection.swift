import SwiftUI

/// What the product sheet on a batch's screen was asked to open for: a new
/// product, or one already recorded.
struct BatchProductEditTarget: Identifiable {
    let id = UUID()
    let product: BatchProduct?
}

/// The products a batch made, as the maker recorded them: a row to add one,
/// then each size and how many. Like the log, written after the batch was made
/// and never part of its snapshot.
///
/// The section only records what it wants shown; the screen presents the
/// sheet, so it opens whichever row has scrolled away.
struct BatchProductsSection: View {
    let batch: Batch
    @Binding var editTarget: BatchProductEditTarget?

    var body: some View {
        let products = batch.products
        Section {
            HoneyLedgerActionRow("Add Product", systemImage: "plus") {
                editTarget = BatchProductEditTarget(product: nil)
            }
            .ledgerSheetRow(position: .position(index: 0, count: products.count + 1))
            ForEach(Array(products.enumerated()), id: \.element.id) { index, product in
                Button {
                    editTarget = BatchProductEditTarget(product: product)
                } label: {
                    HStack {
                        Text(product.quantityLabel)
                            .font(.body.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.ink)
                        Spacer(minLength: 0)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete") {
                        batch.products.removeAll { $0.id == product.id }
                    }
                    .tint(Color.danger)
                    // The sheet's row style would otherwise reach the swipe
                    // buttons, and the list then stops offering them.
                    .buttonStyle(.automatic)
                }
                .ledgerSheetRow(position: .position(index: index + 1, count: products.count + 1))
            }
        } header: {
            HoneyLedgerSectionLabel("Products made")
        } footer: {
            if products.isEmpty {
                HoneyLedgerFooter("Record what this batch made, such as 18 × 100 g.")
            }
        }
    }
}
