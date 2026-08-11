import SwiftData
import Foundation
import SwiftUI

@Observable
final class RecipeListViewModel {
    /// Animated so the row's move to or from the pinned group reads as a move
    /// rather than a jump.
    func toggleFavorite(_ recipe: Recipe) {
        withAnimation {
            recipe.isFavorite.toggle()
        }
    }

    func delete(_ recipe: Recipe, context: ModelContext) {
        context.delete(recipe)
    }
}
