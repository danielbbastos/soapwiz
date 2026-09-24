import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Recipe list bulk delete", .serialized)
@MainActor
struct RecipeListDeleteTests {

    private let sut = RecipeListViewModel()

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    private func insertRecipes(_ names: [String], in context: ModelContext) throws -> [Recipe] {
        let recipes = names.map { Recipe(name: $0) }
        recipes.forEach(context.insert)
        try context.save()
        return recipes
    }

    private func select(_ recipes: [Recipe]) {
        sut.beginSelecting()
        recipes.forEach(sut.toggleSelection(of:))
    }

    // MARK: - Staging

    @Test func requestDeleteSelection_StagesOnlyTheSelectedRecipes() throws {
        let (container, context) = try makeContext()
        _ = container
        let recipes = try insertRecipes(["Castile", "Lavender", "Oatmeal"], in: context)
        select([recipes[0], recipes[2]])

        sut.requestDeleteSelection(from: recipes)

        #expect(sut.confirmingDelete.map(\.name) == ["Castile", "Oatmeal"])
        #expect(sut.isConfirmingDelete)
    }

    @Test func requestDeleteSelection_SelectedRecipeHiddenByFilter_IsStillStaged() throws {
        let (container, context) = try makeContext()
        _ = container
        let recipes = try insertRecipes(["Castile", "Lavender"], in: context)
        let gifts = RecipeCollection(name: "Gifts")
        context.insert(gifts)
        recipes[0].collections.append(gifts)
        select(recipes)
        sut.toggle(gifts)
        #expect(sut.filtered(recipes).map(\.name) == ["Castile"])

        sut.requestDeleteSelection(from: recipes)

        #expect(sut.confirmingDelete.count == 2)
    }

    @Test func requestDeleteSelection_NothingSelected_StagesNothing() throws {
        let (container, context) = try makeContext()
        _ = container
        let recipes = try insertRecipes(["Castile"], in: context)
        sut.beginSelecting()

        sut.requestDeleteSelection(from: recipes)

        #expect(sut.confirmingDelete.isEmpty)
        #expect(!sut.isConfirmingDelete)
    }

    // MARK: - Wording

    @Test func deleteConfirmationTitle_OneRecipe_IsSingular() throws {
        let (container, context) = try makeContext()
        _ = container
        let recipes = try insertRecipes(["Castile"], in: context)
        select(recipes)
        sut.requestDeleteSelection(from: recipes)

        #expect(sut.deleteConfirmationTitle == "Delete 1 Recipe?")
        #expect(sut.deleteButtonTitle == "Delete 1 Recipe")
    }

    @Test func deleteConfirmationTitle_SeveralRecipes_CountsThem() throws {
        let (container, context) = try makeContext()
        _ = container
        let recipes = try insertRecipes(["Castile", "Lavender", "Oatmeal"], in: context)
        select(recipes)
        sut.requestDeleteSelection(from: recipes)

        #expect(sut.deleteConfirmationTitle == "Delete 3 Recipes?")
        #expect(sut.deleteButtonTitle == "Delete 3 Recipes")
    }

    @Test func deleteConfirmationMessage_NoBatches_SaysItCantBeUndone() throws {
        let (container, context) = try makeContext()
        _ = container
        let recipes = try insertRecipes(["Castile", "Lavender"], in: context)
        select(recipes)
        sut.requestDeleteSelection(from: recipes)

        let names = ["Castile", "Lavender"].abbreviatedList()
        #expect(sut.deleteConfirmationMessage == "\(names) will be deleted. This can’t be undone.")
    }

    @Test func deleteConfirmationMessage_OneRecipeWithBatches_SaysTheyStayInHistory() throws {
        let (container, context) = try makeContext()
        _ = container
        let recipes = try insertRecipes(["Castile"], in: context)
        context.insert(Batch(recipe: recipes[0], recipeName: "Castile", batchCount: 1))
        try context.save()
        select(recipes)
        sut.requestDeleteSelection(from: recipes)

        #expect(sut.deleteConfirmationMessage == "Castile will be deleted. Batches made from it stay in History.")
    }

    @Test func deleteConfirmationMessage_ManyRecipes_AbbreviatesTheNames() throws {
        let (container, context) = try makeContext()
        _ = container
        let recipes = try insertRecipes(["A", "B", "C", "D", "E"], in: context)
        context.insert(Batch(recipe: recipes[4], recipeName: "E", batchCount: 1))
        try context.save()
        select(recipes)
        sut.requestDeleteSelection(from: recipes)

        #expect(sut.deleteConfirmationMessage
            == "A, B, C and 2 others will be deleted. Batches made from them stay in History.")
    }

    @Test func deleteConfirmationMessage_NothingStaged_IsEmpty() {
        #expect(sut.deleteConfirmationMessage.isEmpty)
    }

    // MARK: - Confirm and cancel

    @Test func confirmDelete_DeletesOnlyTheStagedRecipesAndEndsSelecting() throws {
        let (container, context) = try makeContext()
        _ = container
        let recipes = try insertRecipes(["Castile", "Lavender", "Oatmeal"], in: context)
        select([recipes[0], recipes[1]])
        sut.requestDeleteSelection(from: recipes)

        sut.confirmDelete(context: context)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<Recipe>())
        #expect(remaining.map(\.name) == ["Oatmeal"])
        #expect(sut.confirmingDelete.isEmpty)
        #expect(!sut.isSelecting)
        #expect(!sut.hasSelection)
    }

    @Test func confirmDelete_KeepsTheBatchHistory() throws {
        let (container, context) = try makeContext()
        _ = container
        let recipes = try insertRecipes(["Castile", "Lavender"], in: context)
        context.insert(Batch(recipe: recipes[0], recipeName: "Castile", batchCount: 1))
        context.insert(Batch(recipe: recipes[1], recipeName: "Lavender", batchCount: 2))
        try context.save()
        select(recipes)
        sut.requestDeleteSelection(from: recipes)

        sut.confirmDelete(context: context)
        try context.save()

        let batches = try context.fetch(FetchDescriptor<Batch>(sortBy: [SortDescriptor(\.recipeName)]))
        #expect(batches.map(\.recipeName) == ["Castile", "Lavender"])
        #expect(batches.allSatisfy { $0.recipe == nil })
    }

    @Test func cancelDelete_KeepsTheRecipesAndTheSelection() throws {
        let (container, context) = try makeContext()
        _ = container
        let recipes = try insertRecipes(["Castile", "Lavender"], in: context)
        select(recipes)
        sut.requestDeleteSelection(from: recipes)

        sut.cancelDelete()

        #expect(try context.fetchCount(FetchDescriptor<Recipe>()) == 2)
        #expect(!sut.isConfirmingDelete)
        #expect(sut.isSelecting)
        #expect(sut.selectedRecipes.count == 2)
    }

    // MARK: - Name abbreviation

    @Test func abbreviatedList_AtTheLimit_ListsEveryName() {
        let names = ["A", "B", "C"]
        #expect(names.abbreviatedList() == names.formatted())
    }

    @Test func abbreviatedList_OneOverTheLimit_SaysOneOther() {
        #expect(["A", "B", "C", "D"].abbreviatedList() == "A, B, C and 1 other")
    }

    @Test func abbreviatedList_Empty_IsEmpty() {
        #expect([String]().abbreviatedList().isEmpty)
    }
}
