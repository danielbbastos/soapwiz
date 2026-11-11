import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Home shopping list")
@MainActor
struct HomeShoppingListTests {

    private let container: ModelContainer
    private let context: ModelContext
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let schema = ModelContainerFactory.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        context = container.mainContext
    }

    private func offset(_ seconds: TimeInterval) -> Date {
        now.addingTimeInterval(seconds)
    }

    private func makeIngredient(_ name: String = "Olive Oil", threshold: Double? = nil) -> Ingredient {
        let ingredient = Ingredient(name: name, unit: "g")
        ingredient.lowStockThreshold = threshold
        context.insert(ingredient)
        return ingredient
    }

    @discardableResult
    private func makeItem(
        _ name: String = "Olive Oil",
        ingredient: Ingredient?,
        isChecked: Bool = false
    ) -> ShoppingListItem {
        let item = ShoppingListItem(name: name, ingredient: ingredient)
        item.createdAt = now
        item.isChecked = isChecked
        context.insert(item)
        return item
    }

    @discardableResult
    private func makePurchase(
        of ingredient: Ingredient,
        remaining: Double = 1000,
        savedAt: Date?
    ) -> IngredientPurchase {
        let purchase = IngredientPurchase(
            provider: nil,
            dateOfPurchase: savedAt ?? now,
            quantity: 1000,
            totalPrice: 10,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        purchase.remainingAmount = remaining
        purchase.createdAt = savedAt
        context.insert(purchase)
        purchase.attach(to: ingredient)
        return purchase
    }

    private func summary(
        items: [ShoppingListItem],
        ingredients: [Ingredient] = [],
        purchases: [IngredientPurchase] = [],
        tracksInventory: Bool = true
    ) -> HomeShoppingList.Summary? {
        HomeShoppingList.make(
            items: items,
            ingredients: ingredients,
            purchases: purchases,
            tracksInventory: tracksInventory,
            now: now
        )
    }

    @Test func make_TickedLine_IsNotCountedToBuy() {
        let ticked = makeItem("Soda", ingredient: nil, isChecked: true)
        let open = makeItem("Lard", ingredient: nil)

        #expect(summary(items: [ticked, open])?.toBuyCount == 1)
    }

    @Test func make_LinkedLineWithLaterPurchase_IsNotCountedToBuy() {
        let ingredient = makeIngredient()
        let bought = makeItem(ingredient: ingredient)
        let other = makeItem("Lard", ingredient: nil)
        let purchase = makePurchase(of: ingredient, savedAt: offset(60))

        let result = summary(items: [bought, other], ingredients: [ingredient], purchases: [purchase])

        #expect(result?.toBuyCount == 1)
    }

    @Test func make_UnlinkedLine_IsCountedToBuy() {
        let item = makeItem("Mica", ingredient: nil)

        #expect(summary(items: [item]) == HomeShoppingList.Summary(toBuyCount: 1, suggestedCount: 0))
    }

    @Test func make_LinkedLineWithOnlyOlderPurchases_IsCountedToBuy() {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient)
        let purchase = makePurchase(of: ingredient, savedAt: offset(-60))

        let result = summary(items: [item], ingredients: [ingredient], purchases: [purchase])

        #expect(result?.toBuyCount == 1)
    }

    @Test func make_IngredientAlreadyListedEvenTicked_IsNotSuggested() {
        let ingredient = makeIngredient(threshold: 500)
        let item = makeItem(ingredient: ingredient, isChecked: true)
        let purchase = makePurchase(of: ingredient, remaining: 0, savedAt: offset(-60))

        let result = summary(items: [item], ingredients: [ingredient], purchases: [purchase])

        #expect(result == nil)
    }

    @Test func make_LowIngredientNotOnList_IsSuggested() {
        let ingredient = makeIngredient(threshold: 500)
        let purchase = makePurchase(of: ingredient, remaining: 100, savedAt: offset(-60))

        let result = summary(items: [], ingredients: [ingredient], purchases: [purchase])

        #expect(result == HomeShoppingList.Summary(toBuyCount: 0, suggestedCount: 1))
    }

    @Test func make_OutIngredientNotOnList_IsSuggested() {
        let ingredient = makeIngredient()
        let purchase = makePurchase(of: ingredient, remaining: 0, savedAt: offset(-60))

        let result = summary(items: [], ingredients: [ingredient], purchases: [purchase])

        #expect(result?.suggestedCount == 1)
    }

    @Test func make_TrackingOff_ReturnsNil() {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: nil)
        let purchase = makePurchase(of: ingredient, remaining: 0, savedAt: offset(-60))

        #expect(summary(items: [item], ingredients: [ingredient], purchases: [purchase], tracksInventory: false) == nil)
    }

    @Test func make_NothingToBuyOrSuggest_ReturnsNil() {
        let ingredient = makeIngredient(threshold: 50)
        let ticked = makeItem("Soda", ingredient: nil, isChecked: true)
        let purchase = makePurchase(of: ingredient, remaining: 900, savedAt: offset(-60))

        #expect(summary(items: [ticked], ingredients: [ingredient], purchases: [purchase]) == nil)
        #expect(summary(items: []) == nil)
    }
}
