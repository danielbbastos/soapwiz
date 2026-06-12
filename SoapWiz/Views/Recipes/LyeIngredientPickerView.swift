import SwiftUI
import SwiftData

struct LyeIngredientPickerView: View {
    @Binding var selected: Ingredient?
    @Environment(\.dismiss) private var dismiss
    @Query private var ingredients: [Ingredient]
    @State private var searchText: String = ""

    private var lyeIngredients: [Ingredient] {
        ingredients
            .filter { $0.category?.name == IngredientCategory.Name.lyes }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var filtered: [Ingredient] {
        guard !searchText.isEmpty else { return lyeIngredients }
        return lyeIngredients.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            if lyeIngredients.isEmpty {
                ContentUnavailableView(
                    "No lye ingredients",
                    systemImage: "tray",
                    description: Text("Add an ingredient to the \"Lyes\" category.")
                )
            } else {
                ForEach(filtered) { ingredient in
                    Button {
                        selected = ingredient
                        dismiss()
                    } label: {
                        HStack {
                            Text(ingredient.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selected?.persistentModelID == ingredient.persistentModelID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
                .listRowBackground(Color.cardBackground)
            }
        }
        .searchable(text: $searchText)
        .navigationTitle("Lye ingredient")
        .navigationBarTitleDisplayMode(.inline)
        .warmNavigationTitle("Lye ingredient")
        .warmBackground()
    }
}
