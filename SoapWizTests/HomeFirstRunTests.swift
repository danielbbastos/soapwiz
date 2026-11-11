import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Home first run")
@MainActor
struct HomeFirstRunTests {

    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        let schema = ModelContainerFactory.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        context = container.mainContext
    }

    private func libraryIngredient(_ slug: String = "olive-oil") -> Ingredient {
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ingredient.librarySlug = slug
        context.insert(ingredient)
        return ingredient
    }

    private func purchase(of ingredient: Ingredient, remaining: Double) -> IngredientPurchase {
        let purchase = IngredientPurchase(
            provider: nil,
            dateOfPurchase: .now,
            quantity: 1000,
            totalPrice: 10,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        purchase.remainingAmount = remaining
        context.insert(purchase)
        purchase.attach(to: ingredient)
        return purchase
    }

    private func isEmpty(
        recipes: [Recipe] = [],
        batches: [Batch] = [],
        shoppingItems: [ShoppingListItem] = [],
        ingredients: [Ingredient] = [],
        purchases: [IngredientPurchase] = []
    ) -> Bool {
        HomeFirstRun.isEmpty(
            recipes: recipes,
            batches: batches,
            shoppingItems: shoppingItems,
            ingredients: ingredients,
            purchases: purchases
        )
    }

    @Test func nothing_IsEmpty() {
        #expect(isEmpty())
    }

    @Test func onlyInstalledLibraryIngredients_IsEmpty() {
        let ingredients = [libraryIngredient("olive-oil"), libraryIngredient("coconut-oil")]

        #expect(isEmpty(ingredients: ingredients))
    }

    @Test func oneRecipe_IsNotEmpty() {
        let recipe = Recipe(name: "Castile")
        context.insert(recipe)

        #expect(!isEmpty(recipes: [recipe]))
    }

    @Test func oneBatch_IsNotEmpty() {
        let batch = Batch(recipe: nil, recipeName: "Castile", batchCount: 1)
        context.insert(batch)

        #expect(!isEmpty(batches: [batch]))
    }

    @Test func oneShoppingItem_IsNotEmpty() {
        let item = ShoppingListItem(name: "Lye", ingredient: nil)
        context.insert(item)

        #expect(!isEmpty(shoppingItems: [item]))
    }

    @Test func customIngredient_IsNotEmpty() {
        let ingredient = Ingredient(name: "My Oil", unit: "g")
        context.insert(ingredient)

        #expect(!isEmpty(ingredients: [ingredient]))
    }

    @Test func libraryIngredientWithPurchase_IsNotEmpty() {
        let ingredient = libraryIngredient()
        let bought = purchase(of: ingredient, remaining: 500)

        #expect(!isEmpty(ingredients: [ingredient], purchases: [bought]))
    }

    @Test func libraryIngredientWithUsedUpPurchase_IsNotEmpty() {
        let ingredient = libraryIngredient()
        let bought = purchase(of: ingredient, remaining: 0)

        #expect(!isEmpty(ingredients: [ingredient], purchases: [bought]))
    }

    @Test func starredLibraryIngredient_IsNotEmpty() {
        let ingredient = libraryIngredient()
        ingredient.isFavorite = true

        #expect(!isEmpty(ingredients: [ingredient]))
    }

    @Test func libraryIngredientWithCustomChemistry_IsNotEmpty() {
        let ingredient = libraryIngredient()
        ingredient.hasCustomChemistry = true

        #expect(!isEmpty(ingredients: [ingredient]))
    }

    @Test func otherIngredientsPurchase_DoesNotOwnThisOne() {
        let owned = libraryIngredient("olive-oil")
        let other = libraryIngredient("coconut-oil")
        let bought = purchase(of: owned, remaining: 100)

        #expect(IngredientOwnership.isOwned(owned, stock: StockLevels([bought])))
        #expect(!IngredientOwnership.isOwned(other, stock: StockLevels([bought])))
    }

    @Test func ownership_MatchesInventoryScope() {
        let custom = Ingredient(name: "Mine", unit: "g")
        context.insert(custom)
        let plain = libraryIngredient("plain")
        let starred = libraryIngredient("starred")
        starred.isFavorite = true
        let bought = libraryIngredient("bought")
        let purchases = [purchase(of: bought, remaining: 0)]
        let stock = StockLevels(purchases)
        let model = IngredientListViewModel()

        for ingredient in [custom, plain, starred, bought] {
            #expect(model.isOwned(ingredient, stock: stock) == IngredientOwnership.isOwned(ingredient, stock: stock))
        }
        #expect(!IngredientOwnership.isOwned(plain, stock: stock))
    }

    @Test func navigationRequests_SetRequestAndTab() {
        let sut = AppNavigation()

        sut.openInventoryImport()
        #expect(sut.pendingInventoryImport != nil)
        #expect(sut.selectedTab == .inventory)

        sut.openRecipeImport()
        #expect(sut.pendingRecipesLaunch?.kind == .importRecipe)
        #expect(sut.selectedTab == .recipes)

        sut.selectedTab = .home
        sut.openStarterRecipes()
        #expect(sut.pendingRecipesLaunch?.kind == .starterLibrary)
        #expect(sut.selectedTab == .recipes)
    }

    @Test func repeatedRequests_AreDistinct() {
        let sut = AppNavigation()

        sut.openInventoryImport()
        let firstImport = sut.pendingInventoryImport
        sut.openInventoryImport()
        #expect(sut.pendingInventoryImport != firstImport)

        sut.openStarterRecipes()
        let firstLaunch = sut.pendingRecipesLaunch
        sut.openStarterRecipes()
        #expect(sut.pendingRecipesLaunch != firstLaunch)
    }

    @Test func takingARequest_HandsItOutOnce() {
        let sut = AppNavigation()
        sut.openInventoryImport()
        sut.openStarterRecipes()

        #expect(sut.takePendingInventoryImport(tourCoverOnScreen: false) != nil)
        #expect(sut.takePendingInventoryImport(tourCoverOnScreen: false) == nil)
        #expect(sut.takePendingRecipesLaunch(tourCoverOnScreen: false)?.kind == .starterLibrary)
        #expect(sut.takePendingRecipesLaunch(tourCoverOnScreen: false) == nil)
    }

    @Test func takingARequest_WaitsForTheTourCover() {
        let sut = AppNavigation()
        sut.openInventoryImport()
        sut.openRecipeImport()

        #expect(sut.takePendingInventoryImport(tourCoverOnScreen: true) == nil)
        #expect(sut.takePendingRecipesLaunch(tourCoverOnScreen: true) == nil)
        #expect(sut.pendingInventoryImport != nil)
        #expect(sut.pendingRecipesLaunch != nil)
    }

    @Test func takingARequest_WaitsForADetailSheet() {
        let sut = AppNavigation()
        sut.detailSheetRequest = .createBatch(Recipe(name: "Castile"))
        sut.openRecipeImport()

        #expect(sut.takePendingRecipesLaunch(tourCoverOnScreen: false) == nil)
        #expect(sut.pendingRecipesLaunch != nil)
    }
}
