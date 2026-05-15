import SwiftUI
import SwiftData

struct RecipeIngredientDraft: Identifiable {
    let id = UUID()
    let ingredient: Ingredient
    var percentage: String = ""
}

@Observable
final class RecipeFormViewModel {
    var name: String = ""
    var desc: String = ""
    var ingredientDrafts: [RecipeIngredientDraft] = []

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    func addIngredient(_ ingredient: Ingredient) {
        guard !ingredientDrafts.contains(where: {
            $0.ingredient.persistentModelID == ingredient.persistentModelID
        }) else { return }
        ingredientDrafts.append(RecipeIngredientDraft(ingredient: ingredient))
    }

    func removeIngredient(at offsets: IndexSet) {
        ingredientDrafts.remove(atOffsets: offsets)
    }

    @discardableResult
    func save(context: ModelContext) -> Recipe {
        let recipe = Recipe(
            name: name.trimmingCharacters(in: .whitespaces),
            desc: desc.trimmingCharacters(in: .whitespaces)
        )
        context.insert(recipe)
        for draft in ingredientDrafts {
            let pct = Double(draft.percentage.replacingOccurrences(of: ",", with: ".")) ?? 0
            let ri = RecipeIngredient(ingredient: draft.ingredient, percentage: pct)
            ri.recipe = recipe
            context.insert(ri)
        }
        return recipe
    }
}
