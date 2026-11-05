import SwiftUI
import SwiftData

/// The bundled starter recipes, to browse and copy from. Looking is free; only
/// a copy takes one of the free tier's recipe slots.
struct StarterRecipeLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FreeTierGateEnvironment private var freeTier
    @Query(sort: \Ingredient.name) private var inventory: [Ingredient]
    @Query(sort: \RecipeCollection.name) private var collections: [RecipeCollection]
    @Query(sort: \IngredientCategory.name) private var categories: [IngredientCategory]
    @Query(sort: \Recipe.name) private var recipes: [Recipe]

    @State private var library: StarterRecipeLibrary?
    @State private var loadFailed = false
    @State private var copyFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if let library {
                    list(library)
                } else if loadFailed {
                    HoneyLedgerEmptyState(
                        "Starter Recipes Unavailable",
                        systemImage: "book.closed",
                        description: "The starter recipes couldn’t be opened."
                    )
                }
            }
            .navigationTitle("Starter Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle("Starter Recipes")
            .ledgerBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Couldn’t Copy Recipe", isPresented: $copyFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("That recipe couldn’t be saved. Please try again.")
            }
        }
        .presentationSizing(.page)
        .proUpgradeHost()
        .task {
            guard library == nil else { return }
            do {
                library = try StarterRecipeLibrary()
            } catch {
                loadFailed = true
            }
        }
    }

    private func list(_ library: StarterRecipeLibrary) -> some View {
        List {
            Section {
                ForEach(library.previews) { preview in
                    NavigationLink(value: preview.index) {
                        row(preview, isInYourRecipes: library.isInYourRecipes(preview, among: recipes))
                    }
                    .ledgerSheetRow(
                        position: .position(index: preview.index, count: library.previews.count),
                        navigates: true
                    )
                }
            } footer: {
                HoneyLedgerFooter("Copies become your own recipes to edit. Check the numbers before you make them.")
            }
        }
        .navigationDestination(for: Int.self) { index in
            if library.previews.indices.contains(index) {
                let preview = library.previews[index]
                StarterRecipePreviewView(recipe: preview.recipe) {
                    copy(preview, from: library)
                }
            }
        }
    }

    private func row(_ preview: StarterRecipePreview, isInYourRecipes: Bool) -> some View {
        let summary = RecipeRowSummary(recipe: preview.recipe, compositionLimit: nil)
        return VStack(alignment: .leading, spacing: 2) {
            Text(preview.recipe.name)
                .font(.headline)
                .foregroundStyle(Color.ink)
            if let composition = summary.composition {
                Text(composition)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Color.inkSoft)
            }
            if !preview.recipe.desc.isEmpty {
                Text(preview.recipe.desc)
                    .font(.footnote)
                    .foregroundStyle(Color.inkSoft)
                    .lineLimit(2)
            }
            if isInYourRecipes {
                Text("In your recipes")
                    .font(.caption)
                    .foregroundStyle(Color.inkFaint)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copy(_ preview: StarterRecipePreview, from library: StarterRecipeLibrary) {
        freeTier.ifMayCreateRecipe(in: modelContext) {
            let fileable = freeTier.gate.allows(.collections) ? collections : []
            guard library.copy(
                preview,
                inventory: inventory,
                collections: fileable,
                recipes: recipes,
                categories: categories,
                into: modelContext
            ) != nil else {
                copyFailed = true
                return
            }
            dismiss()
        }
    }
}
