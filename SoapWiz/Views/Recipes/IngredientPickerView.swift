import SwiftUI
import SwiftData

struct IngredientPickerView: View {
    @Query(sort: \Ingredient.name) private var allIngredients: [Ingredient]
    @Query(sort: \IngredientCategory.name) private var allCategories: [IngredientCategory]
    @Environment(\.dismiss) private var dismiss

    let addedIDs: Set<PersistentIdentifier>
    var allowedRole: RecipeIngredientRole? = nil
    let onSelect: ([Ingredient]) -> Void

    @State private var searchText = ""
    @State private var selectedCategory: IngredientCategory?
    @State private var pendingSelections: Set<PersistentIdentifier> = []

    private var categories: [IngredientCategory] {
        guard let role = allowedRole else { return allCategories }
        return allCategories.filter { $0.ingredientRole == role }
    }

    private var filtered: [Ingredient] {
        allIngredients.filter { ingredient in
            let matchesAllowed = allowedRole.map { ingredient.category?.ingredientRole == $0 } ?? true
            let matchesSearch = searchText.isEmpty ||
                ingredient.name.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategory == nil ||
                ingredient.category?.persistentModelID == selectedCategory?.persistentModelID
            return matchesAllowed && matchesSearch && matchesCategory
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !categories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("All", isSelected: selectedCategory == nil) {
                                selectedCategory = nil
                            }
                            ForEach(categories) { category in
                                chip(category.name,
                                     isSelected: selectedCategory?.persistentModelID == category.persistentModelID) {
                                    selectedCategory = category
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    }
                    Divider()
                }
                List {
                    ForEach(filtered, id: \.persistentModelID) { ingredient in
                        ingredientRow(ingredient)
                    }
                }
            }
            .navigationTitle("Choose Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search ingredients")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let selected = allIngredients.filter { pendingSelections.contains($0.persistentModelID) }
                        onSelect(selected)
                        dismiss()
                    }
                    .disabled(pendingSelections.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func ingredientRow(_ ingredient: Ingredient) -> some View {
        let isAdded = addedIDs.contains(ingredient.persistentModelID)
        let isPending = pendingSelections.contains(ingredient.persistentModelID)
        Button {
            guard !isAdded else { return }
            if isPending {
                pendingSelections.remove(ingredient.persistentModelID)
            } else {
                pendingSelections.insert(ingredient.persistentModelID)
            }
        } label: {
            HStack {
                Text(ingredient.name)
                Spacer()
                if isAdded {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                } else if isPending {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(isAdded)
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemFill))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
