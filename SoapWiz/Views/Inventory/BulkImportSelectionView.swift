import SwiftUI
import SwiftData

/// First step of bulk import: pick which existing ingredients should receive a new
/// purchase. Tapping rows toggles selection; "Next" starts the sequential entry
/// flow with the chosen ingredients in name order.
struct BulkImportSelectionView: View {
    @Query(sort: \Ingredient.name) private var ingredients: [Ingredient]

    @State private var selection: Set<PersistentIdentifier> = []
    @State private var searchText = ""

    let onCancel: () -> Void
    let onStart: ([Ingredient]) -> Void

    private var selectedIngredients: [Ingredient] {
        ingredients.filter { selection.contains($0.persistentModelID) }
    }

    private var filteredIngredients: [Ingredient] {
        guard !searchText.isEmpty else { return ingredients }
        return ingredients.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if ingredients.isEmpty {
                    ContentUnavailableView(
                        "No Ingredients",
                        systemImage: "flask",
                        description: Text("Add ingredients before importing purchases.")
                    )
                } else {
                    List {
                        ForEach(filteredIngredients) { ingredient in
                            Button {
                                toggle(ingredient)
                            } label: {
                                HStack {
                                    Image(systemName: selection.contains(ingredient.persistentModelID)
                                          ? "checkmark.circle.fill"
                                          : "circle")
                                        .foregroundStyle(selection.contains(ingredient.persistentModelID)
                                                         ? Color.accentColor : .secondary)
                                    Text(ingredient.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .listRowBackground(Color.cardBackground)
                        }
                    }
                    .overlay {
                        if filteredIngredients.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        }
                    }
                    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search ingredients")
                }
            }
            .navigationTitle("Bulk Import")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle("Bulk Import")
            .warmBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") { onStart(selectedIngredients) }
                        .disabled(selection.isEmpty)
                }
            }
        }
    }

    private func toggle(_ ingredient: Ingredient) {
        let id = ingredient.persistentModelID
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }
}
