import Foundation
import SwiftData
import SwiftUI

extension IngredientListViewModel {
    /// Animated so the row's move to or from the pinned group reads as a move
    /// rather than a jump.
    func toggleFavorite(_ ingredient: Ingredient) {
        withAnimation {
            ingredient.isFavorite.toggle()
        }
    }

    /// Hiding is immediate and needs no confirmation: nothing is lost, the row keeps
    /// its purchases, recipes already built on it are untouched, and Unhide is one tap
    /// away in the filter sheet.
    func hide(_ ingredient: Ingredient) {
        withAnimation {
            ingredient.isHidden = true
        }
    }

    func unhide(_ ingredient: Ingredient) {
        withAnimation {
            ingredient.isHidden = false
        }
    }

    /// A library row is hidden rather than deleted, and recipe usage doesn't stand in
    /// the way: hiding leaves the ingredient in place for every recipe already
    /// pointing at it.
    ///
    /// For a user-created row, being used by a recipe blocks deletion outright and
    /// takes precedence over the remaining-stock confirmation: losing stock is
    /// recoverable, silently gutting a recipe's oil percentages — and with them its
    /// lye calculation — is not.
    ///
    /// Everything else routes through `confirmingDelete`. An ingredient carries sap
    /// values, density and a fatty-acid profile that are tedious to re-enter, and
    /// there is no undo, so no deletion happens on a single tap.
    func delete(_ ingredient: Ingredient) {
        guard !ingredient.isLibraryInstalled else {
            hide(ingredient)
            return
        }
        if ingredient.isUsedInRecipes {
            deleteBlockedIngredients = [ingredient]
        } else {
            confirmingDelete = [ingredient]
        }
    }

    /// If any selected user-created ingredient is used by a recipe, nothing happens at
    /// all — a partial removal would be harder to reason about than none. Library rows
    /// in the same selection are staged for hiding, which no recipe can block.
    func deleteSelected(in ingredients: [Ingredient]) {
        let targets = selection.compactMap { id in ingredients.first { $0.persistentModelID == id } }
        guard !targets.isEmpty else { return }
        let deletable = targets.filter { !$0.isLibraryInstalled }
        let blocked = deletable.filter(\.isUsedInRecipes)
        if !blocked.isEmpty {
            deleteBlockedIngredients = blocked
        } else {
            confirmingHide = targets.filter(\.isLibraryInstalled)
            confirmingDelete = deletable
        }
    }

    var isConfirmingRemoval: Bool { !confirmingDelete.isEmpty || !confirmingHide.isEmpty }

    func cancelRemoval() {
        confirmingDelete = []
        confirmingHide = []
    }

    /// Titles the confirmation for what it will actually do, which depends on the mix:
    /// a selection can be all library rows, all user-created ones, or both.
    var removalConfirmationTitle: String {
        if confirmingHide.isEmpty {
            return confirmingDelete.count == 1 ? "Delete Ingredient?" : "Delete Ingredients?"
        }
        if confirmingDelete.isEmpty {
            return confirmingHide.count == 1 ? "Hide Ingredient?" : "Hide Ingredients?"
        }
        return "Remove Ingredients?"
    }

    /// Spells the hide out whenever library rows are involved. "Delete" is the word
    /// the user reached for, and being told that some rows are only hidden — and where
    /// to find them again — is the whole point of the confirmation.
    var removalConfirmationMessage: String {
        guard !confirmingHide.isEmpty else { return deleteConfirmationMessage }

        let hidePart: String
        if confirmingHide.count == 1, let name = confirmingHide.first?.name {
            hidePart = "\"\(name)\" is a library ingredient, so it will be hidden rather than deleted. "
                + "You can bring it back from Filters."
        } else {
            hidePart = "\(confirmingHide.count) library ingredients will be hidden rather than deleted. "
                + "You can bring them back from Filters."
        }

        guard !confirmingDelete.isEmpty else { return hidePart }
        return hidePart + "\n\n" + deleteConfirmationMessage
    }

    /// Explains which recipes are in the way, so the user knows where to go next.
    var deleteBlockedMessage: String {
        guard !deleteBlockedIngredients.isEmpty else { return "" }

        if deleteBlockedIngredients.count == 1, let ingredient = deleteBlockedIngredients.first {
            let recipes = ingredient.recipesUsingThis.map(\.name).sorted()
            let target = recipes.count == 1 ? "that recipe" : "those recipes"
            return "\"\(ingredient.name)\" is used in \(recipes.abbreviatedList()). "
                + "Remove it from \(target) first."
        }

        let names = deleteBlockedIngredients.map(\.name).sorted()
        return "\(names.abbreviatedList()) are used in recipes. Remove them from those recipes first."
    }

    /// Message for the delete confirmation. Lives here rather than in the view so the
    /// wording is testable.
    var deleteConfirmationMessage: String {
        guard !confirmingDelete.isEmpty else { return "" }

        let purchaseCount = confirmingDelete.reduce(0) { $0 + $1.purchases.count }
        guard purchaseCount > 0 else {
            if confirmingDelete.count == 1, let name = confirmingDelete.first?.name {
                return "Delete \"\(name)\"? This can't be undone."
            }
            return "Delete \(confirmingDelete.count) ingredients? This can't be undone."
        }

        let ingredientWord = confirmingDelete.count == 1 ? "ingredient" : "ingredients"
        let purchaseWord = purchaseCount == 1 ? "purchase" : "purchases"
        return "Deleting \(confirmingDelete.count) \(ingredientWord) will also delete "
            + "\(purchaseCount) \(purchaseWord). This can't be undone."
    }

    /// Applies both halves of the staged removal: library rows are hidden, the rest
    /// deleted.
    func confirmDelete(context: ModelContext) {
        confirmingHide.forEach { $0.isHidden = true }
        confirmingDelete.forEach { $0.deleteWithOwnedRows(in: context) }
        context.saveLoggingFailure()
        confirmingHide = []
        confirmingDelete = []
        selection.removeAll()
        editMode = .inactive
    }
}
