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

    /// Whether the list is picking recipes to export rather than opening them.
    ///
    /// A mode of its own rather than SwiftUI's `editMode`: the rows are `Button`s
    /// so they can drop the disclosure chevron, which puts them outside what
    /// `List(selection:)` drives, and in regular width that selection draws a
    /// border there is no modifier to suppress.
    var isSelecting = false

    /// Recipes ticked for export. Cleared whenever the mode ends, so leaving and
    /// re-entering never starts with someone else's selection.
    var selectedRecipes: Set<PersistentIdentifier> = []

    /// Set when an export file is ready; presents the share sheet.
    var exportFile: ExportFile?

    /// User-facing message for the export step.
    var exportErrorMessage: String?

    var hasActiveFilters: Bool { !selectedCollections.isEmpty }

    var hasSelection: Bool { !selectedRecipes.isEmpty }

    /// The navigation title, which carries the count while selecting.
    ///
    /// The count belongs here rather than on the share button: a compact toolbar
    /// collapses a `Label` to its icon, so a count in the button's title is
    /// invisible on iPhone. Putting it in the title is also what Mail, Photos
    /// and Files all do.
    var navigationTitle: String {
        guard isSelecting else { return "Recipes" }
        switch selectedRecipes.count {
        case 0: return "Select Recipes"
        case 1: return "1 Selected"
        default: return "\(selectedRecipes.count) Selected"
        }
    }

    /// Spoken by VoiceOver on the share button, where the visible label is only
    /// an icon.
    var exportButtonTitle: String {
        selectedRecipes.count == 1 ? "Share 1 Recipe" : "Share \(selectedRecipes.count) Recipes"
    }

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

    // MARK: - Selection

    func beginSelecting() {
        withAnimation {
            isSelecting = true
            selectedRecipes = []
        }
    }

    func endSelecting() {
        withAnimation {
            isSelecting = false
            selectedRecipes = []
        }
    }

    func isSelected(_ recipe: Recipe) -> Bool {
        selectedRecipes.contains(recipe.persistentModelID)
    }

    func toggleSelection(of recipe: Recipe) {
        let id = recipe.persistentModelID
        if selectedRecipes.contains(id) {
            selectedRecipes.remove(id)
        } else {
            selectedRecipes.insert(id)
        }
    }

    /// The selected recipes in the order the list shows them, so the exported
    /// file reads the way the screen did rather than in set order.
    func selection(from recipes: [Recipe]) -> [Recipe] {
        recipes.filter { selectedRecipes.contains($0.persistentModelID) }
    }

    /// Builds the export file and hands it to the share sheet. Ends the
    /// selection mode on success — the job the user entered it for is done.
    func exportSelection(from recipes: [Recipe]) {
        let selected = selection(from: recipes)
        guard !selected.isEmpty else { return }
        do {
            exportFile = try RecipeTransferExport.file(for: selected)
            endSelecting()
        } catch {
            exportErrorMessage = "Couldn’t prepare those recipes for sharing. Please try again."
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
        UIPasteboard.general.string = RecipeTextExporter.clipboardText(for: recipe)
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
