import Testing
import Foundation
import SwiftData
@testable import SoapWiz

// MARK: - Recipe form

@Suite("Recipe form collections", .serialized)
@MainActor
struct RecipeFormCollectionTests: RecipeFormTestHelpers {

    @Test func selectedCollections_NewForm_IsEmpty() {
        #expect(RecipeFormViewModel().selectedCollections.isEmpty)
    }

    @Test func toggleCollection_Once_SelectsIt() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let gifts = RecipeCollection(name: "Gifts")
        ctx.insert(gifts)
        let model = RecipeFormViewModel()

        model.toggleCollection(gifts)

        #expect(model.isSelected(gifts))
        #expect(model.selectedCollections.count == 1)
    }

    @Test func toggleCollection_Twice_DeselectsIt() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let gifts = RecipeCollection(name: "Gifts")
        ctx.insert(gifts)
        let model = RecipeFormViewModel()

        model.toggleCollection(gifts)
        model.toggleCollection(gifts)

        #expect(model.isSelected(gifts) == false)
        #expect(model.selectedCollections.isEmpty)
    }

    /// Selection order must not leak into the stored order, or the dirty check
    /// would fire on a recipe the user only re-picked in a different sequence.
    @Test func toggleCollection_SelectedOutOfOrder_StaysSortedByName() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let gifts = RecipeCollection(name: "Gifts")
        let christmas = RecipeCollection(name: "Christmas")
        ctx.insert(gifts)
        ctx.insert(christmas)
        let model = RecipeFormViewModel()

        model.toggleCollection(gifts)
        model.toggleCollection(christmas)

        #expect(model.selectedCollections.map(\.name) == ["Christmas", "Gifts"])
    }

    @Test func collectionsLabel_NoneSelected_ReadsNone() {
        #expect(RecipeFormViewModel().collectionsLabel == "None")
    }

    @Test func collectionsLabel_OneSelected_ReadsItsName() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let gifts = RecipeCollection(name: "Gifts")
        ctx.insert(gifts)
        let model = RecipeFormViewModel()
        model.toggleCollection(gifts)

        #expect(model.collectionsLabel == "Gifts")
    }

    @Test func collectionsLabel_SeveralSelected_CountsThem() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let collections = ["Gifts", "Christmas"].map { RecipeCollection(name: $0) }
        collections.forEach { ctx.insert($0) }
        let model = RecipeFormViewModel()
        collections.forEach { model.toggleCollection($0) }

        #expect(model.collectionsLabel == "2 selected")
    }

    // MARK: - Persistence

    @Test func save_WithCollections_FilesTheRecipeUnderEach() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        let gifts = RecipeCollection(name: "Gifts")
        ctx.insert(christmas)
        ctx.insert(gifts)

        let model = RecipeFormViewModel()
        model.name = "Cinnamon Bar"
        model.toggleCollection(christmas)
        model.toggleCollection(gifts)
        let recipe = model.save(context: ctx)
        try ctx.save()

        #expect(Set(recipe.collections.map(\.name)) == ["Christmas", "Gifts"])
        #expect(christmas.recipes.map(\.name) == ["Cinnamon Bar"])
    }

    @Test func save_NoCollections_LeavesTheRecipeUnfiled() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let model = RecipeFormViewModel()
        model.name = "Castile"
        let recipe = model.save(context: ctx)
        try ctx.save()

        #expect(recipe.collections.isEmpty)
    }

    @Test func load_FiledRecipe_ReadsItsCollectionsSorted() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        let gifts = RecipeCollection(name: "Gifts")
        let recipe = Recipe(name: "Cinnamon Bar")
        ctx.insert(christmas)
        ctx.insert(gifts)
        ctx.insert(recipe)
        recipe.collections = [gifts, christmas]
        try ctx.save()

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.selectedCollections.map(\.name) == ["Christmas", "Gifts"])
        #expect(model.isSelected(gifts))
    }

    @Test func save_AfterDeselecting_UnfilesTheRecipe() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        let recipe = Recipe(name: "Cinnamon Bar")
        ctx.insert(christmas)
        ctx.insert(recipe)
        recipe.collections = [christmas]
        try ctx.save()

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        model.toggleCollection(christmas)
        model.save(context: ctx)
        try ctx.save()

        #expect(recipe.collections.isEmpty)
        #expect(christmas.recipes.isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<RecipeCollection>()).count == 1)
    }

    // MARK: - Unsaved changes

    @Test func isDirty_CollectionToggled_IsTrue() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let gifts = RecipeCollection(name: "Gifts")
        ctx.insert(gifts)
        let model = RecipeFormViewModel()
        model.captureSnapshot()

        model.toggleCollection(gifts)

        #expect(model.isDirty)
    }

    @Test func isDirty_CollectionToggledBackOff_IsFalseAgain() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let gifts = RecipeCollection(name: "Gifts")
        ctx.insert(gifts)
        let model = RecipeFormViewModel()
        model.captureSnapshot()

        model.toggleCollection(gifts)
        model.toggleCollection(gifts)

        #expect(model.isDirty == false)
    }

    @Test func isDirty_LoadedFiledRecipeUntouched_IsFalse() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let christmas = RecipeCollection(name: "Christmas")
        let gifts = RecipeCollection(name: "Gifts")
        let recipe = Recipe(name: "Cinnamon Bar")
        ctx.insert(christmas)
        ctx.insert(gifts)
        ctx.insert(recipe)
        recipe.collections = [gifts, christmas]
        try ctx.save()

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        model.captureSnapshot()

        #expect(model.isDirty == false)
    }
}
