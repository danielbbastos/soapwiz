import SwiftUI
import SwiftData

struct IngredientPickerView: View {
    @Query(sort: \Ingredient.name) private var allIngredients: [Ingredient]
    @Query(sort: \IngredientCategory.name) private var allCategories: [IngredientCategory]
    @Query private var settingsRecords: [AppSettings]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

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
    @State private var showsInStockOnly = false
    @State private var pendingSelections = PendingIngredientSelection()
    @State private var showingNewIngredient = false

    /// Whether an ingredient or category with the given role is offered by a
    /// picker configured with these options. A `nil` role is the "Others"
    /// bucket; a `nil` `allowedRoles` offers every role.
    static func accepts(role: RecipeIngredientRole?, allowedRoles: Set<RecipeIngredientRole>?, includesUnroled: Bool) -> Bool {
        guard let allowedRoles else { return true }
        guard let role else { return includesUnroled }
        return allowedRoles.contains(role)
    }

    private var tracksInventory: Bool { AppSettings.tracksInventory(from: settingsRecords) }

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
        IngredientPickerFilter(
            searchText: searchText,
            category: selectedCategory,
            inStockOnly: showsInStockOnly && tracksInventory
        )
        .choices(from: allIngredients, allowedRoles: allowedRoles, includesUnroled: includesUnroled)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchField("Search ingredients", text: $searchText)
                    .padding(.top, 8)
                if !categories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip("All", isSelected: selectedCategory == nil) {
                                selectedCategory = nil
                            }
                            if tracksInventory {
                                FilterChip("In stock", isSelected: showsInStockOnly) {
                                    showsInStockOnly.toggle()
                                }
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
            // Every device installs its own categories, so the first sync on a
            // joining device merges the chip's copy away. Kept, it would empty
            // the list and reach "Add new ingredient" as a row that traps when
            // read. Its name is gone with it, so the chip falls back to All.
            .onReceive(NotificationCenter.default.publisher(for: .duplicatesMerged)) { _ in
                if selectedCategory?.modelContext == nil {
                    selectedCategory = nil
                }
                pendingSelections.followMerge(in: modelContext)
            }
            .sheet(isPresented: $showingNewIngredient) {
                IngredientFormView(defaultCategory: defaultCategory) { newIngredient in
                    pendingSelections.insert(newIngredient)
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
            pendingSelections.toggle(ingredient)
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
