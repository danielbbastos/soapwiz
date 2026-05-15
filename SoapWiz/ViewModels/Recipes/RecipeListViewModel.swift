import SwiftData
import Foundation

@Observable
final class RecipeListViewModel {
    func delete(_ recipe: Recipe, context: ModelContext) {
        context.delete(recipe)
    }
}
