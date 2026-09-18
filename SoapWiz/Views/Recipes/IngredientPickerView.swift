import SwiftUI
import SwiftData

struct IngredientPickerView: View {
    @Query(sort: \Ingredient.name) private var allIngredients: [Ingredient]
    @Query(sort: \IngredientCategory.name) private var allCategories: [IngredientCategory]
    @Environment(\.dismiss) private var dismiss

    let addedIDs: Set<PersistentIdentifier>

    /// Roles the picker will offer. `nil` means every role. A non-soap recipe's
    /// merged Ingredients section passes both `.oil` and `.additive`, so waxes,
    /// fats, butters and additives all appear in one list.
    var allowedRoles: Set<RecipeIngredientRole>?
    /// Whether categories with no `ingredientRole` — the "Others" bucket — are
    /// also offered. A non-soap recipe's Ingredients section sets this so a
    /// general ingredient that is neither oil, additive nor fragrance can still
    /// be chosen; soap pickers leave it off.
    var includesUnroled = false
    let onSelect: ([Ingredient]) -> Void

    @State private var searchText = ""
    @State private var selectedCategory: IngredientCategory?
    @State private var pendingSelections: Set<PersistentIdentifier> = []
    @State private var showingNewIngredient = false

    /// Whether an ingredient or category with the given role is offered by a
    /// picker configured with these options. A `nil` role is the "Others"
    /// bucket; a `nil` `allowedRoles` offers every role.
    static func accepts(role: RecipeIngredientRole?, allowedRoles: Set<RecipeIngredientRole>?, includesUnroled: Bool) -> Bool {
        guard let allowedRoles else { return true }
        guard let role else { return includesUnroled }
        return allowedRoles.contains(role)
    }

    private var categories: [IngredientCategory] {
        allCategories.filter { category in
            Self.accepts(role: category.ingredientRole, allowedRoles: allowedRoles, includesUnroled: includesUnroled)
        }
    }

    /// Category to pre-select when creating a new ingredient inline: the chosen
    /// chip if any, otherwise the first category matching the picker's role.
    private var defaultCategory: IngredientCategory? {
        selectedCategory ?? categories.first
    }

    private var filtered: [Ingredient] {
        allIngredients.filter { ingredient in
            // Hiding an ingredient is the user saying they don't use it, so it
            // leaves the choices here too, not just Inventory. Unhiding from
            // Filters is the way back.
            guard !ingredient.isHidden else { return false }

            let matchesAllowed = Self.accepts(
                role: ingredient.category?.ingredientRole,
                allowedRoles: allowedRoles,
                includesUnroled: includesUnroled
            )
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
                            FilterChip("All", isSelected: selectedCategory == nil) {
                                selectedCategory = nil
                            }
                            ForEach(categories) { category in
                                FilterChip(
                                    category.name,
                                    isSelected: selectedCategory?.persistentModelID == category.persistentModelID
                                ) {
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
                    Button {
                        showingNewIngredient = true
                    } label: {
                        Label("Add new ingredient", systemImage: "plus")
                    }
                    .listRowBackground(Color.cardBackground)
                    ForEach(filtered, id: \.persistentModelID) { ingredient in
                        ingredientRow(ingredient)
                    }
                }
            }
            .navigationTitle("Choose Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle("Choose Ingredient")
            .warmBackground()
            .searchable(text: $searchText, prompt: "Search ingredients")
            .sheet(isPresented: $showingNewIngredient) {
                IngredientFormView(defaultCategory: defaultCategory) { newIngredient in
                    pendingSelections.insert(newIngredient.persistentModelID)
                }
            }
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
                // Leading, so the state stays visible under a right hand — and
                // matching the extras rows, which already put it here.
                Image(systemName: isAdded || isPending ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isPending ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                Text(ingredient.name)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .disabled(isAdded)
        .listRowBackground(isPending ? Color.selectedRowBackground : Color.cardBackground)
    }
}
