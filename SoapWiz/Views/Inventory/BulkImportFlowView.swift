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
            // Fresh identity per entry so advancing to the next ingredient resets the
            // scroll position to the top instead of staying where the last one was.
            .id(model.position)
            .navigationTitle(model.currentIngredient.name)
            .navigationBarTitleDisplayMode(.inline)
            .warmBackground()
            .safeAreaInset(edge: .top, spacing: 0) {
                Text(model.currentIngredient.name)
                    .font(.title2.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.warmInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(Color.warmBackground)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(model.progressText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
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
