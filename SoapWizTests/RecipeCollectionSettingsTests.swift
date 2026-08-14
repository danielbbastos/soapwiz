import Testing
import Foundation
import SwiftData
@testable import SoapWiz

// MARK: - Settings screens

@Suite("Recipe collection form view model", .serialized)
@MainActor
struct RecipeCollectionFormViewModelTests: RecipeCollectionTestHelpers {

    @Test func isValid_BlankName_IsFalse() {
        let model = RecipeCollectionFormViewModel()
        model.name = "   "

        #expect(model.isValid(among: []) == false)
    }

    @Test func isDuplicate_NameDifferingByCaseAndSpacing_IsTrue() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let existing = RecipeCollection(name: "Christmas")
        ctx.insert(existing)
        let model = RecipeCollectionFormViewModel()
        model.name = "  christmas "

        #expect(model.isDuplicate(among: [existing]))
        #expect(model.isValid(among: [existing]) == false)
    }

    /// Editing a collection without renaming it must not report the collection as
    /// its own duplicate.
    @Test func isDuplicate_EditingItself_IsFalse() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let existing = RecipeCollection(name: "Christmas")
        ctx.insert(existing)
        let model = RecipeCollectionFormViewModel(collection: existing)

        #expect(model.isDuplicate(among: [existing]) == false)
        #expect(model.isValid(among: [existing]))
    }

    @Test func save_NewCollection_InsertsWithTrimmedNameAndColor() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeCollectionFormViewModel()
        model.name = "  Gifts  "
        model.color = .teal

        let saved = model.save(context: ctx)
        try ctx.save()

        #expect(saved.name == "Gifts")
        #expect(saved.colorName == "teal")
        #expect(try ctx.fetch(FetchDescriptor<RecipeCollection>()).count == 1)
    }

    @Test func save_ExistingCollection_MutatesItAndKeepsItsRecipes() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let collection = RecipeCollection(name: "Xmas")
        let recipe = Recipe(name: "Cinnamon Bar")
        ctx.insert(collection)
        ctx.insert(recipe)
        recipe.collections = [collection]
        try ctx.save()

        let model = RecipeCollectionFormViewModel(collection: collection)
        model.name = "Christmas"
        model.color = .red
        model.save(context: ctx)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<RecipeCollection>()).count == 1)
        #expect(collection.name == "Christmas")
        #expect(collection.color == .red)
        #expect(collection.recipes.count == 1)
    }

    @Test func init_ExistingCollection_LoadsNameAndColor() {
        let model = RecipeCollectionFormViewModel(
            collection: RecipeCollection(name: "Gifts", colorName: "purple")
        )

        #expect(model.name == "Gifts")
        #expect(model.color == .purple)
        #expect(model.isEditing)
    }
}

@Suite("Recipe collection list view model", .serialized)
@MainActor
struct RecipeCollectionListViewModelTests: RecipeCollectionTestHelpers {

    @Test func delete_InUseCollection_ConfirmsRatherThanBlocking() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        let recipe = Recipe(name: "Cinnamon Bar")
        ctx.insert(christmas)
        ctx.insert(recipe)
        recipe.collections = [christmas]
        try ctx.save()

        let model = RecipeCollectionListViewModel()
        model.delete(at: IndexSet(integer: 0), in: [christmas])

        #expect(model.confirmingDelete.count == 1)
        #expect(try ctx.fetch(FetchDescriptor<RecipeCollection>()).count == 1)
    }

    @Test func confirmDelete_RemovesCollectionAndLeavesRecipesIntact() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        let recipe = Recipe(name: "Cinnamon Bar")
        ctx.insert(christmas)
        ctx.insert(recipe)
        recipe.collections = [christmas]
        try ctx.save()

        let model = RecipeCollectionListViewModel()
        model.delete(at: IndexSet(integer: 0), in: [christmas])
        model.confirmDelete(context: ctx)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<RecipeCollection>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Recipe>()).count == 1)
        #expect(recipe.collections.isEmpty)
        #expect(model.confirmingDelete.isEmpty)
    }

    @Test func delete_OutOfRangeOffset_StagesNothing() {
        let model = RecipeCollectionListViewModel()
        model.delete(at: IndexSet(integer: 3), in: [RecipeCollection(name: "Gifts")])

        #expect(model.confirmingDelete.isEmpty)
    }

    @Test func deleteConfirmationMessage_NothingStaged_IsEmpty() {
        #expect(RecipeCollectionListViewModel().deleteConfirmationMessage.isEmpty)
    }

    @Test func deleteConfirmationMessage_EmptyCollection_DoesNotMentionRecipes() {
        let model = RecipeCollectionListViewModel()
        model.delete(at: IndexSet(integer: 0), in: [RecipeCollection(name: "Gifts")])

        #expect(model.deleteConfirmationMessage == "Delete \"Gifts\"? This can't be undone.")
    }

    /// The promise that recipes survive is the reason this alert confirms instead
    /// of blocking, so the wording is asserted rather than left to the view.
    @Test func deleteConfirmationMessage_CollectionWithRecipes_PromisesTheyAreKept() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        ctx.insert(christmas)
        for name in ["Cinnamon Bar", "Spiced Gift Bar"] {
            let recipe = Recipe(name: name)
            ctx.insert(recipe)
            recipe.collections = [christmas]
        }
        try ctx.save()

        let model = RecipeCollectionListViewModel()
        model.delete(at: IndexSet(integer: 0), in: [christmas])

        #expect(model.deleteConfirmationMessage
            == "Delete \"Christmas\"? Its 2 recipes are kept and simply unfiled.")
    }

    @Test func deleteConfirmationMessage_SingleRecipe_UsesTheSingular() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        let recipe = Recipe(name: "Cinnamon Bar")
        ctx.insert(christmas)
        ctx.insert(recipe)
        recipe.collections = [christmas]
        try ctx.save()

        let model = RecipeCollectionListViewModel()
        model.delete(at: IndexSet(integer: 0), in: [christmas])

        #expect(model.deleteConfirmationMessage
            == "Delete \"Christmas\"? Its 1 recipe is kept and simply unfiled.")
    }

    @Test func deleteConfirmationMessage_SeveralCollections_CountsThemTogether() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        let gifts = RecipeCollection(name: "Gifts")
        let recipe = Recipe(name: "Cinnamon Bar")
        ctx.insert(christmas)
        ctx.insert(gifts)
        ctx.insert(recipe)
        recipe.collections = [christmas, gifts]
        try ctx.save()

        let model = RecipeCollectionListViewModel()
        model.delete(at: IndexSet([0, 1]), in: [christmas, gifts])

        #expect(model.deleteConfirmationMessage
            == "Delete 2 collections? Their 2 recipes are kept and simply unfiled.")
    }
}
