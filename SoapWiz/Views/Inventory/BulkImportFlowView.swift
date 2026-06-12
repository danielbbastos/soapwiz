import SwiftUI
import SwiftData

/// Sequential purchase entry for a bulk import. Shows the shared purchase form for
/// each selected ingredient in turn, with a "N of M" progress indicator. Reuses
/// `PurchaseFormFields` rather than duplicating the form.
struct BulkImportFlowView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var model: BulkImportFlowViewModel
    /// Called when the queue is exhausted or the user cancels — dismisses the flow.
    let onFinish: () -> Void

    init(ingredients: [Ingredient], onFinish: @escaping () -> Void) {
        _model = State(initialValue: BulkImportFlowViewModel(ingredients: ingredients))
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            Form {
                PurchaseFormFields(model: model.currentForm)
            }
            .navigationTitle(model.currentIngredient.name)
            .navigationBarTitleDisplayMode(.inline)
            .warmBackground()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(model.currentIngredient.name)
                            .font(.title3.weight(.bold))
                            .fontDesign(.rounded)
                            .foregroundStyle(Color.warmInk)
                        Text(model.progressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinish() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button("Skip") { advance() }
                    Button(model.isLastStep ? "Done" : "Add") {
                        model.commitAndAdvance(context: modelContext)
                        finishIfComplete()
                    }
                    .disabled(!model.canCommit)
                }
            }
        }
    }

    private func advance() {
        model.skip()
        finishIfComplete()
    }

    private func finishIfComplete() {
        if model.isComplete { onFinish() }
    }
}
