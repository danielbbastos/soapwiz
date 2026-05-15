import SwiftUI
import SwiftData

struct RecipeFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var model = RecipeFormViewModel()
    var onSave: ((Recipe) -> Void)?

    var body: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $model.name)
                TextField("Description", text: $model.desc, axis: .vertical)
                    .lineLimit(3...6)
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
    }
}
