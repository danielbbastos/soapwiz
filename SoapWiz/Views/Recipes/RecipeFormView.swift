import SwiftUI
import SwiftData

struct RecipeFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var model = RecipeFormViewModel()
    @State private var showingPicker = false
    var onSave: ((Recipe) -> Void)?

    var body: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $model.name)
                TextField("Description", text: $model.desc, axis: .vertical)
                    .lineLimit(3...6)
            }
            Section("Ingredients") {
                ForEach($model.ingredientDrafts) { $draft in
                    HStack {
                        Text(draft.ingredient.name)
                        Spacer()
                        TextField("0", text: $draft.percentage)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("%")
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { model.removeIngredient(at: $0) }
                Button {
                    showingPicker = true
                } label: {
                    Label("Add ingredient", systemImage: "plus")
                }
            }
        }
        .navigationTitle("New Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let recipe = model.save(context: modelContext)
                    onSave?(recipe)
                    dismiss()
                }
                .disabled(!model.canSave)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .sheet(isPresented: $showingPicker) {
            IngredientPickerView(
                addedIDs: Set(model.ingredientDrafts.map(\.ingredient.persistentModelID)),
                onSelect: model.addIngredient
            )
        }
    }
}
