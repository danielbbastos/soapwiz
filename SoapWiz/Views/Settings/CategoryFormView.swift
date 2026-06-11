import SwiftUI
import SwiftData

struct CategoryFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \IngredientCategory.name) private var allCategories: [IngredientCategory]

    @State private var model: CategoryFormViewModel

    init(category: IngredientCategory? = nil) {
        _model = State(initialValue: CategoryFormViewModel(category: category))
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
                        model.save(context: modelContext)
                        dismiss()
                    }
                    .disabled(!model.isValid(among: allCategories))
                }
            }
        }
    }
}
