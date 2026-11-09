import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Counts the fetches the recipe rows make, and fails them on demand.
@MainActor
final class RecipeFetchCounter {
    struct Failure: Error {}

    private(set) var count = 0
    var shouldFail = false

    func fetch(_ context: ModelContext) throws -> [Recipe] {
        count += 1
        if shouldFail { throw Failure() }
        return try RecipeRows.fetchAll(in: context)
    }
}

/// When the recipe rows refetch, and when they leave the list alone (SW-364).
@Suite("Recipe rows", .serialized)
@MainActor
struct RecipeRowsTests: InventoryRowsTestHelpers {

    private func insertRemotely(_ name: String, in container: ModelContainer) throws {
        let other = ModelContext(container)
        other.insert(Recipe(name: name))
        try other.save()
    }

    @Test func init_FetchesRecipesByName() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(Recipe(name: "Rose"))
        context.insert(Recipe(name: "Almond"))
        context.insert(Recipe(name: "Lavender"))
        try context.save()

        let sut = RecipeRows(context: context)

        #expect(sut.recipes.map(\.name) == ["Almond", "Lavender", "Rose"])
    }

    @Test func save_InsertsRecipe_RefetchesAndShowsIt() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let counter = RecipeFetchCounter()
        let sut = RecipeRows(context: context, fetchRecipes: counter.fetch)
        let fetchesBefore = counter.count

        context.insert(Recipe(name: "Lavender"))
        try context.save()

        #expect(counter.count == fetchesBefore + 1)
        #expect(sut.recipes.map(\.name) == ["Lavender"])
    }

    @Test func save_EditsRecipeIngredient_Refetches() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let recipe = Recipe(name: "Lavender")
        context.insert(recipe)
        let line = RecipeIngredient(ingredient: nil, percentage: 50, role: .oil)
        line.recipe = recipe
        context.insert(line)
        try context.save()
        let counter = RecipeFetchCounter()
        let sut = RecipeRows(context: context, fetchRecipes: counter.fetch)
        let fetchesBefore = counter.count

        line.percentage = 60
        try context.save()

        #expect(counter.count == fetchesBefore + 1)
        #expect(sut.recipes.count == 1)
    }

    @Test func save_OnlyIngredient_DoesNotRefetch() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let counter = RecipeFetchCounter()
        let sut = RecipeRows(context: context, fetchRecipes: counter.fetch)
        let fetchesBefore = counter.count

        context.insert(Ingredient(name: "Lye", unit: "g"))
        try context.save()

        #expect(counter.count == fetchesBefore)
        #expect(sut.recipes.isEmpty)
    }

    @Test func import_OtherContextSavesRecipe_RefetchesOnlyWhenImportFinishes() throws {
        let container = try makeContainer()
        let counter = RecipeFetchCounter()
        let sut = RecipeRows(context: container.mainContext, fetchRecipes: counter.fetch)
        let fetchesBefore = counter.count

        try insertRemotely("Lavender", in: container)
        #expect(counter.count == fetchesBefore)
        #expect(sut.recipes.isEmpty)

        sut.handle(importEnd)

        #expect(counter.count == fetchesBefore + 1)
        #expect(sut.recipes.map(\.name) == ["Lavender"])
    }

    @Test func import_OnlyUnrelatedChanges_DoesNotRefetch() throws {
        let container = try makeContainer()
        let counter = RecipeFetchCounter()
        let sut = RecipeRows(context: container.mainContext, fetchRecipes: counter.fetch)
        let fetchesBefore = counter.count
        let other = ModelContext(container)
        other.insert(Ingredient(name: "Olive Oil", unit: "g"))
        try other.save()

        sut.handle(importEnd)

        #expect(counter.count == fetchesBefore)
    }

    @Test func handle_Export_DoesNothing() throws {
        let container = try makeContainer()
        let counter = RecipeFetchCounter()
        let sut = RecipeRows(context: container.mainContext, fetchRecipes: counter.fetch)
        let fetchesBefore = counter.count
        try insertRemotely("Lavender", in: container)

        sut.handle(SyncEvent(kind: .export, endDate: .now, succeeded: true, error: nil))

        #expect(counter.count == fetchesBefore)
    }

    @Test func settlingMerge_MergeSavesRecipes_RefetchesOnce() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let counter = RecipeFetchCounter()
        let sut = RecipeRows(context: context, fetchRecipes: counter.fetch)
        let fetchesBefore = counter.count

        sut.settlingMerge {
            context.insert(Recipe(name: "A"))
            try? context.save()
            context.insert(Recipe(name: "B"))
            try? context.save()
        }

        #expect(counter.count == fetchesBefore + 1)
        #expect(sut.recipes.count == 2)
    }

    @Test func prune_ImportRunning_DropsDeletedRecipeWithoutFetching() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = Recipe(name: "First")
        let second = Recipe(name: "Second")
        context.insert(first)
        context.insert(second)
        try context.save()
        let counter = RecipeFetchCounter()
        let sut = RecipeRows(context: context, pruneInterval: .milliseconds(10), fetchRecipes: counter.fetch)
        let fetchesBefore = counter.count
        #expect(sut.recipes.count == 2)

        sut.handle(importStart)
        context.delete(first)
        await waitUntil { sut.recipes.count == 1 }

        #expect(sut.recipes.first === second)
        #expect(counter.count == fetchesBefore)
    }

    @Test func fetch_Fails_KeepsOldRowsAndNextCheckRetries() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let counter = RecipeFetchCounter()
        let sut = RecipeRows(context: context, fetchRecipes: counter.fetch)
        context.insert(Recipe(name: "Lavender"))
        try context.save()
        #expect(sut.recipes.count == 1)

        counter.shouldFail = true
        context.insert(Recipe(name: "Rose"))
        try context.save()
        #expect(sut.recipes.map(\.name) == ["Lavender"])

        counter.shouldFail = false
        let didRefetch = sut.refreshIfRecipesChanged()

        #expect(didRefetch)
        #expect(sut.recipes.count == 2)
    }
}
