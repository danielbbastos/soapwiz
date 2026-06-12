import SwiftUI
import SwiftData

struct PurchaseFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var model: PurchaseFormViewModel

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
                        model.save(context: modelContext)
                        dismiss()
                    }
                    .disabled(!model.isValid)
                }
            }
        }
    }
}
