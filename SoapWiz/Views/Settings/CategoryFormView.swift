import SwiftUI
import SwiftData

struct CategoryFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \IngredientCategory.name) private var allCategories: [IngredientCategory]

    var category: IngredientCategory? = nil

    @State private var name: String

    init(category: IngredientCategory? = nil) {
        self.category = category
        _name = State(initialValue: category?.name ?? "")
    }

    private var isEditing: Bool { category != nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var isDuplicate: Bool {
        guard !trimmedName.isEmpty else { return false }
        return allCategories.contains { $0.name.lowercased() == trimmedName.lowercased() && $0 != category }
    }

    private var isValid: Bool { !trimmedName.isEmpty && !isDuplicate }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                } footer: {
                    if isDuplicate {
                        Text("A category with this name already exists.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Category" : "New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        save()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        if let category {
            category.name = trimmedName
        } else {
            modelContext.insert(IngredientCategory(name: trimmedName))
        }
    }
}
