import SwiftUI
import SwiftData

struct IngredientPickerView: View {
    @Query(sort: \Ingredient.name) private var allIngredients: [Ingredient]
    @Query(sort: \IngredientCategory.name) private var categories: [IngredientCategory]
    @Environment(\.dismiss) private var dismiss

    let addedIDs: Set<PersistentIdentifier>
    let onSelect: (Ingredient) -> Void

    @State private var searchText = ""
    @State private var selectedCategory: IngredientCategory?

    private var filtered: [Ingredient] {
        allIngredients.filter { ingredient in
            let matchesSearch = searchText.isEmpty ||
                ingredient.name.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategory == nil ||
                ingredient.category?.persistentModelID == selectedCategory?.persistentModelID
            return matchesSearch && matchesCategory
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
                List(filtered) { ingredient in
                    let isAdded = addedIDs.contains(ingredient.persistentModelID)
                    Button {
                        onSelect(ingredient)
                        dismiss()
                    } label: {
                        HStack {
                            Text(ingredient.name)
                            Spacer()
                            if isAdded {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .disabled(isAdded)
                }
            }
            .navigationTitle("Choose Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search ingredients")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
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
