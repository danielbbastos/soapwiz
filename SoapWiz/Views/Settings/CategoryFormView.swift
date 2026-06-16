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
                    TextField("Name", text: $model.name)
                } footer: {
                    if model.isDuplicate(among: allCategories) {
                        Text("A category with this name already exists.")
                            .foregroundStyle(.red)
                    }
                }
                .listRowBackground(Color.cardBackground)
            }
            .navigationTitle(model.isEditing ? "Edit Category" : "New Category")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle(model.isEditing ? "Edit Category" : "New Category")
            .warmBackground()
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
        }
    }
}
