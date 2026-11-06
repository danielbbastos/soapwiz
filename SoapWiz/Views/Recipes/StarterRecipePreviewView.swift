import SwiftUI
import SwiftData

/// A starter recipe, read-only: the recipe detail's own description, amounts and
/// stats, with a button to copy it into the user's recipes in place of the
/// detail's actions. `recipe` belongs to the library's throwaway store.
struct StarterRecipePreviewView: View {
    let recipe: Recipe
    let onCopy: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var model = RecipeFormViewModel()
    @State private var showInGrams = false

    var body: some View {
        let batch = model.wholeBatchBreakdown
        List {
            Section {
                if !recipe.desc.isEmpty {
                    HoneyLedgerNote(recipe.desc)
                        .padding(.vertical, 4)
                        .ledgerSheetRow(position: .only)
                }
            } header: {
                HoneyLedgerOrnament()
                    .padding(.top, -10)
            }

            RecipeDetailIngredientSections(model: model, batch: batch, showInGrams: $showInGrams)
            RecipeDetailStatsSections(stats: RecipeStats(oilDrafts: model.oilDrafts, makesSoap: model.makesSoap))
        }
        .readableWidth()
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .honeyLedgerInlineTitle(recipe.name)
        .ledgerBackground()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: onCopy) {
                    Text(horizontalSizeClass == .compact ? "Copy" : "Copy Recipe")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.amberText)
                }
                .accessibilityLabel("Copy to My Recipes")
            }
        }
        .task(id: recipe.persistentModelID) {
            model.load(from: recipe)
        }
    }
}
