import SwiftData
import Foundation

@Observable
final class RecipeListViewModel {
    var showingAddRecipe = false

    func delete(_ recipe: Recipe, context: ModelContext) {
        context.delete(recipe)
    }
}
