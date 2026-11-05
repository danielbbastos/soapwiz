import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite
@MainActor
struct StarterRecipesTests {

    private let fixture: RecipeTransferFixture
    private let free = FreeTierGate(isPro: false)

    init() throws {
        fixture = try RecipeTransferFixture()
        try IngredientLibraryInstaller.installMissing(from: .bundled, in: fixture.context)
        try fixture.context.save()
    }

    private func starterPayload() throws -> RecipeTransferData {
        try StarterRecipes.payload()
    }

    private func copy(_ preview: StarterRecipePreview, from library: StarterRecipeLibrary) throws -> Recipe {
        try #require(
            library.copy(preview, includingCollections: false, into: fixture.context)
        )
    }

    // MARK: - Bundled data

    @Test func payload_Bundled_DecodesFourRecipesInOrder() throws {
        let payload = try starterPayload()

        #expect(payload.recipes.map(\.name) == ["Classic Castile", "Simple Palm Bar", "Palm-Free Bar", "Salt Bar"])
        #expect(payload.hasResolvableIngredientIndices)
        #expect(payload.ingredients.count == 5)
    }

    @Test func payload_Bundled_RecipesHaveUniqueIdentities() throws {
        let payload = try starterPayload()
        let identities = Set(payload.recipes.compactMap(\.uuid))

        #expect(identities.count == payload.recipes.count)
    }

    @Test func payload_PoolIngredients_MatchLibraryChemistry() throws {
        let payload = try starterPayload()

        for incoming in payload.ingredients {
            let slug = try #require(incoming.librarySlug)
            let entry = try #require(IngredientLibrary.bundled.entries.first { $0.slug == slug })
            #expect(incoming.name == entry.name)
            #expect(incoming.unit == entry.unit)
            #expect(incoming.sapValue == entry.sapValue)
            #expect(incoming.kohSapValue == entry.kohSapValue)
            #expect(incoming.density == entry.density)
            #expect(incoming.fattyAcidProfile == entry.fattyAcidProfile)
        }
    }

    @Test func payload_EachRecipe_OilPercentagesSumToOneHundred() throws {
        let payload = try starterPayload()

        for recipe in payload.recipes {
            let total = recipe.ingredients.reduce(0) { $0 + $1.percentage }
            #expect(abs(total - 100) < 0.0001)
            #expect(recipe.ingredients.allSatisfy { $0.role == RecipeIngredientRole.oil.rawValue })
        }
    }

    // MARK: - Library

    @Test func library_Init_BuildsFourPreviewsAndLeavesTheUserStoreEmpty() throws {
        let library = try StarterRecipeLibrary()

        #expect(library.previews.count == 4)
        #expect(library.previews.map(\.recipe.name) == ["Classic Castile", "Simple Palm Bar", "Palm-Free Bar", "Salt Bar"])
        #expect(try fixture.context.fetchCount(FetchDescriptor<Recipe>()) == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<Ingredient>()) == IngredientLibrary.bundled.entries.count)
    }

    @Test func library_PalmFreeBar_UncappedCompositionIncludesCastorOil() throws {
        let library = try StarterRecipeLibrary()
        let preview = try #require(library.previews.first { $0.recipe.name == "Palm-Free Bar" })

        let composition = try #require(RecipeRowSummary(recipe: preview.recipe, compositionLimit: nil).composition)

        #expect(composition.contains("Castor Oil"))
    }

    @Test func library_Init_MissingResource_Throws() {
        #expect(throws: RecipeTransferError.self) {
            _ = try StarterRecipeLibrary(bundle: Bundle(for: BundleToken.self))
        }
    }

    @Test(arguments: [
        ("Classic Castile", 129.55, 259.09),
        ("Simple Palm Bar", 142.75, 328.32),
        ("Palm-Free Bar", 142.40, 299.05),
        ("Salt Bar", 139.84, 279.68)
    ])
    func lye_PreviewRecipe_MatchesHandComputedValues(name: String, naoh: Double, water: Double) throws {
        let library = try StarterRecipeLibrary()
        let preview = try #require(library.previews.first { $0.recipe.name == name })
        let model = RecipeFormViewModel()
        model.load(from: preview.recipe)

        let lye = try #require(model.calculatedNaOHLyeAmount)
        let batchWater = try #require(model.calculatedWaterAmount)

        #expect(abs(lye - naoh) < 0.01)
        #expect(abs(batchWater - water) < 0.01)
    }

    // MARK: - In your recipes

    @Test func isInYourRecipes_OnlyForAStarterWhoseUUIDIsHeld() throws {
        let library = try StarterRecipeLibrary()
        let held = try #require(library.previews.first)
        let mine = Recipe(name: "Mine")
        mine.uuid = held.recipe.uuid
        fixture.context.insert(mine)
        try fixture.context.save()
        let recipes = try fixture.context.fetch(FetchDescriptor<Recipe>())

        #expect(library.isInYourRecipes(held, among: recipes))
        #expect(library.previews.dropFirst().allSatisfy { !library.isInYourRecipes($0, among: recipes) })
        #expect(library.previews.allSatisfy { !library.isInYourRecipes($0, among: []) })
    }

    // MARK: - Copy

    @Test func copy_OneStarter_CreatesOneRecipeMatchedBySlugAndNoIngredients() throws {
        let library = try StarterRecipeLibrary()
        let preview = try #require(library.previews.first { $0.recipe.name == "Simple Palm Bar" })
        let ingredientsBefore = try fixture.context.fetchCount(FetchDescriptor<Ingredient>())

        let created = try copy(preview, from: library)

        #expect(try fixture.context.fetchCount(FetchDescriptor<Recipe>()) == 1)
        #expect(try fixture.context.fetchCount(FetchDescriptor<Ingredient>()) == ingredientsBefore)
        #expect(created.name == "Simple Palm Bar")
        #expect(created.uuid == preview.recipe.uuid)
        #expect(created.superFat == 5)
        #expect(created.waterParts == 2.3)
        #expect(created.ingredients.count == 3)
        #expect(created.lyeType == "NaOH" && created.totalOilWeight == 1000)
        let slugs = created.ingredients.compactMap { $0.ingredient?.librarySlug }
        #expect(slugs.count == 3 && slugs.allSatisfy { !$0.isEmpty })
    }

    @Test func copy_SameStarterTwice_CreatesTwoRecipesWithDifferentNamesAndUUIDs() throws {
        let library = try StarterRecipeLibrary()
        let preview = try #require(library.previews.first { $0.recipe.name == "Salt Bar" })

        let first = try copy(preview, from: library)
        let second = try copy(preview, from: library)

        #expect(try fixture.context.fetchCount(FetchDescriptor<Recipe>()) == 2)
        #expect(first.name != second.name)
        #expect(first.uuid != second.uuid)
    }

    @Test func copy_LeavesTheLibraryPreviewsUntouched() throws {
        let library = try StarterRecipeLibrary()
        let preview = try #require(library.previews.first)
        let uuid = preview.recipe.uuid

        _ = try copy(preview, from: library)

        #expect(preview.recipe.uuid == uuid)
        #expect(library.previews.count == 4)
    }

    // MARK: - Free tier

    @Test func canCreateRecipe_ThreeExistingRecipes_FreeGateRefusesTheCopy() throws {
        for index in 0..<3 {
            fixture.context.insert(Recipe(name: "Existing \(index)"))
        }
        try fixture.context.save()

        #expect(!free.canCreateRecipe(in: fixture.context))
        #expect(FreeTierGate(isPro: true).canCreateRecipe(in: fixture.context))
    }

    @Test func canCreateRecipe_TwoExistingRecipes_FreeGateAllowsTheCopy() throws {
        for index in 0..<2 {
            fixture.context.insert(Recipe(name: "Existing \(index)"))
        }
        try fixture.context.save()

        #expect(free.canCreateRecipe(in: fixture.context))
    }
}

private final class BundleToken {}
