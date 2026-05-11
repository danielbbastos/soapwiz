import SwiftUI
import SwiftData

struct IngredientFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \IngredientCategory.name) private var categories: [IngredientCategory]

    @State private var model: IngredientFormViewModel

    init(ingredient: Ingredient? = nil) {
        _model = State(initialValue: IngredientFormViewModel(ingredient: ingredient))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $model.name)
                    Picker("Category", selection: $model.selectedCategory) {
                        Text("None").tag(Optional<IngredientCategory>.none)
                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category))
                        }
                    }
                    TextField("Unit (e.g. g, ml, oz)", text: $model.unit)
                }
            }
            .navigationTitle(model.isEditing ? "Edit Ingredient" : "New Ingredient")
            .navigationBarTitleDisplayMode(.inline)
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
