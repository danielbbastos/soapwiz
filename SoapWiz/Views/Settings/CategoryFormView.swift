import SwiftUI
import SwiftData

struct CategoryFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \IngredientCategory.name) private var allCategories: [IngredientCategory]

    @State private var model: CategoryFormViewModel
    let onSave: ((IngredientCategory) -> Void)?

    init(category: IngredientCategory? = nil, onSave: ((IngredientCategory) -> Void)? = nil) {
        _model = State(initialValue: CategoryFormViewModel(category: category))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HoneyLedgerField(
                        "Name",
                        text: $model.name,
                        prompt: "Required",
                        error: model.isDuplicate(among: allCategories)
                            ? String(localized: "A category with this name already exists.") : nil
                    )
                    .ledgerSheetRow(position: .only)
                }
            }
            .navigationTitle(model.isEditing ? "Edit Category" : "New Category")
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle(model.isEditing ? "Edit Category" : "New Category")
            .ledgerBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isEditing ? "Save" : "Add") {
                        let saved = model.save(context: modelContext)
                        onSave?(saved)
                        dismiss()
                    }
                    .disabled(!model.isValid(among: allCategories))
                }
            }
            .interactiveDismissDisabled(model.isDirty)
        }
    }
}
