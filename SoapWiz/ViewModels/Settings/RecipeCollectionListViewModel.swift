import Foundation
import SwiftData

@MainActor
@Observable
final class RecipeCollectionListViewModel {
    var showingAddCollection: Bool = false
    var collectionToEdit: RecipeCollection?
    var confirmingDelete: [RecipeCollection] = []

    /// Unlike a category, a collection in use doesn't block its own deletion: the
    /// link is `.nullify`, so the recipes survive and are simply unfiled. It
    /// still confirms, because the membership itself is work the user did by
    /// hand and there is no undo.
    func delete(at offsets: IndexSet, in collections: [RecipeCollection]) {
        let targets = offsets.compactMap { collections.indices.contains($0) ? collections[$0] : nil }
        guard !targets.isEmpty else { return }
        confirmingDelete = targets
    }

    /// Message for the delete confirmation. Lives here rather than in the view so
    /// the wording — in particular the promise that recipes are kept — is testable.
    var deleteConfirmationMessage: String {
        guard !confirmingDelete.isEmpty else { return "" }

        let recipeCount = confirmingDelete.reduce(0) { $0 + $1.recipes.count }
        guard recipeCount > 0 else {
            if confirmingDelete.count == 1, let name = confirmingDelete.first?.name {
                return "Delete \"\(name)\"? This can't be undone."
            }
            return "Delete \(confirmingDelete.count) collections? This can't be undone."
        }

        let recipeWord = recipeCount == 1 ? "recipe" : "recipes"
        let verb = recipeCount == 1 ? "is" : "are"
        if confirmingDelete.count == 1, let name = confirmingDelete.first?.name {
            return "Delete \"\(name)\"? Its \(recipeCount) \(recipeWord) \(verb) kept and simply unfiled."
        }
        return "Delete \(confirmingDelete.count) collections? Their \(recipeCount) \(recipeWord) "
            + "\(verb) kept and simply unfiled."
    }

    func confirmDelete(context: ModelContext) {
        confirmingDelete.forEach { context.delete($0) }
        confirmingDelete = []
    }
}
