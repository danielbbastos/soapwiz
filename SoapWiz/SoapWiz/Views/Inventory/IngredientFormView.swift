import SwiftUI
import SwiftData

struct IngredientFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var ingredient: Ingredient? = nil

    @State private var name = ""
    @State private var category = ""
    @State private var unit = ""

    private var isEditing: Bool { ingredient != nil }
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !unit.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Category", text: $category)
                    TextField("Unit (e.g. g, ml, oz)", text: $unit)
                }
            }
            .navigationTitle(isEditing ? "Edit Ingredient" : "New Ingredient")
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
        .onAppear {
            if let ingredient {
                name = ingredient.name
                category = ingredient.category
                unit = ingredient.unit
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedCategory = category.trimmingCharacters(in: .whitespaces)
        let trimmedUnit = unit.trimmingCharacters(in: .whitespaces)

        if let ingredient {
            ingredient.name = trimmedName
            ingredient.category = trimmedCategory
            ingredient.unit = trimmedUnit
        } else {
            modelContext.insert(Ingredient(name: trimmedName, category: trimmedCategory, unit: trimmedUnit))
        }
    }
}
