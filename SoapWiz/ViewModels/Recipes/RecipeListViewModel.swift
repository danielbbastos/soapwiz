import SwiftData
import Foundation

@Observable
final class RecipeListViewModel {
    func toggleFavorite(_ recipe: Recipe) {
        recipe.isFavorite.toggle()
    }

    func delete(_ recipe: Recipe, context: ModelContext) {
        context.delete(recipe)
    }
}
