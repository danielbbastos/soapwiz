import SwiftUI

/// Container for the bulk import sheet. Starts on ingredient selection, then swaps
/// to the sequential entry flow once the user has chosen which ingredients to add
/// purchases to. Dismisses the whole sheet when the flow finishes or is cancelled.
struct BulkImportView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [Ingredient]?

    var body: some View {
        if let queue {
            BulkImportFlowView(ingredients: queue, onFinish: { dismiss() })
        } else {
            BulkImportSelectionView(
                onCancel: { dismiss() },
                onStart: { queue = $0 }
            )
        }
    }
}
