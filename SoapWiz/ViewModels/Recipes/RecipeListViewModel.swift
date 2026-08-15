import SwiftData
import Foundation
import SwiftUI
import UIKit

@MainActor
@Observable
final class RecipeListViewModel {
    /// Collections the list is narrowed to. Empty means "everything" rather than
    /// "nothing" — the chips are a narrowing overlay, not a required choice.
    var selectedCollections: Set<PersistentIdentifier> = []

    /// The recipe whose collections are being edited in the picker sheet.
    var filingRecipe: Recipe?

    var hasActiveFilters: Bool { !selectedCollections.isEmpty }

    /// Recipes in *any* selected collection. The union rather than the
    /// intersection: selecting "Christmas" and "Gifts" asks for both piles, and a
    /// recipe filed under only one of them is still one the user meant to see.
    ///
    /// Filtering happens here rather than in a `#Predicate` because
    /// `collectionsStorage` is an optional to-many, which the store cannot filter
    /// on — see `ModelContainerFactory.schema`.
    func filtered(_ recipes: [Recipe]) -> [Recipe] {
        guard !selectedCollections.isEmpty else { return recipes }
        return recipes.filter { recipe in
            recipe.collections.contains { selectedCollections.contains($0.persistentModelID) }
        }
    }

    /// Drops selections whose collection no longer exists. `DuplicateMerger`
    /// deletes the losing row of a duplicate pair, and a filter still holding its
    /// ID would silently match nothing and show an empty recipe list.
    func pruneSelectedCollections(against collections: [RecipeCollection]) {
        guard !selectedCollections.isEmpty else { return }
        selectedCollections.formIntersection(collections.map(\.persistentModelID))
    }

    func toggle(_ collection: RecipeCollection) {
        let id = collection.persistentModelID
        withAnimation {
            if selectedCollections.contains(id) {
                selectedCollections.remove(id)
            } else {
                selectedCollections.insert(id)
            }
        }
    }

    func clearFilters() {
        withAnimation {
            selectedCollections = []
        }
    }

    // MARK: - Row actions

    /// Files or unfiles a recipe without opening the form. Animated because the
    /// row may leave the list on the spot when a filter is active.
    func toggleMembership(of recipe: Recipe, in collection: RecipeCollection) {
        withAnimation {
            if let index = recipe.collections.firstIndex(where: { $0 === collection }) {
                recipe.collections.remove(at: index)
            } else {
                recipe.collections.append(collection)
            }
        }
    }

    @discardableResult
    func duplicate(_ recipe: Recipe, among recipes: [Recipe], context: ModelContext) -> Recipe {
        withAnimation {
            RecipeDuplicator.duplicate(recipe, among: recipes, into: context)
        }
    }

    func copyToPasteboard(_ recipe: Recipe) {
        UIPasteboard.general.string = RecipeTextExporter.text(for: recipe)
    }

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
