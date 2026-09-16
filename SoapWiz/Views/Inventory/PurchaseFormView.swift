import SwiftUI
import SwiftData

struct PurchaseFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var model: PurchaseFormViewModel
    @State private var saveError: String?

    init(ingredient: Ingredient, purchase: IngredientPurchase? = nil) {
        _model = State(initialValue: PurchaseFormViewModel(ingredient: ingredient, purchase: purchase))
    }

    var body: some View {
        NavigationStack {
            Form {
                PurchaseFormFields(model: model)
            }
            .navigationTitle(model.isEditing ? "Edit Purchase" : "New Purchase")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle(model.isEditing ? "Edit Purchase" : "New Purchase")
            .warmBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isEditing ? "Save" : "Add") {
                        do {
                            try model.save(context: modelContext)
                            dismiss()
                        } catch {
                            // Deliberately stays on the sheet: dismissing would
                            // throw away what the user typed along with the
                            // purchase that could not be written.
                            saveError = error.localizedDescription
                        }
                    }
                    .disabled(!model.isValid)
                }
            }
            .alert(
                "Couldn’t Save Purchase",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveError ?? "")
            }
        }
    }
}
