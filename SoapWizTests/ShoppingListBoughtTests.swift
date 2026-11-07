import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Shopping list bought")
@MainActor
struct ShoppingListBoughtTests {

    private let container: ModelContainer
    private let context: ModelContext
    private let created = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let schema = ModelContainerFactory.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        context = container.mainContext
    }

    private func offset(_ seconds: TimeInterval) -> Date {
        created.addingTimeInterval(seconds)
    }

    private func makeIngredient(_ name: String = "Olive Oil") -> Ingredient {
        let ingredient = Ingredient(name: name, unit: "g")
        context.insert(ingredient)
        return ingredient
    }

    private func makeItem(_ name: String = "Olive Oil", ingredient: Ingredient?) -> ShoppingListItem {
        let item = ShoppingListItem(name: name, ingredient: ingredient)
        item.createdAt = created
        context.insert(item)
        return item
    }

    private func makePurchase(of ingredient: Ingredient, on date: Date, savedAt: Date?) -> IngredientPurchase {
        let purchase = IngredientPurchase(
            provider: nil,
            dateOfPurchase: date,
            quantity: 100,
            totalPrice: 10,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        purchase.createdAt = savedAt
        context.insert(purchase)
        purchase.attach(to: ingredient)
        return purchase
    }

    @Test func dates_PurchaseSavedBeforeItemSameDay_IsNotBought() {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient)
        let purchase = makePurchase(of: ingredient, on: offset(-60), savedAt: offset(-60))

        #expect(ShoppingListBought.dates(items: [item], purchases: [purchase]).isEmpty)
    }

    @Test func dates_PurchaseSavedBeforeItemWithLaterDate_IsNotBought() {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient)
        let purchase = makePurchase(of: ingredient, on: offset(86_400), savedAt: offset(-60))

        #expect(ShoppingListBought.dates(items: [item], purchases: [purchase]).isEmpty)
    }

    @Test func dates_PurchaseSavedAfterItem_IsBoughtWithItsPurchaseDate() {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient)
        let purchaseDate = offset(-3 * 86_400)
        let purchase = makePurchase(of: ingredient, on: purchaseDate, savedAt: offset(60))

        let result = ShoppingListBought.dates(items: [item], purchases: [purchase])

        #expect(result[item.persistentModelID] == purchaseDate)
    }

    @Test func dates_PurchaseSavedAtItemInstant_IsNotBought() {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient)
        let purchase = makePurchase(of: ingredient, on: created, savedAt: created)

        #expect(ShoppingListBought.dates(items: [item], purchases: [purchase]).isEmpty)
    }

    @Test func dates_EditedExistingPurchase_IsNotBought() {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient)
        let purchase = makePurchase(of: ingredient, on: offset(-86_400), savedAt: offset(-86_400))

        purchase.dateOfPurchase = offset(3_600)
        purchase.quantity = 250

        #expect(ShoppingListBought.dates(items: [item], purchases: [purchase]).isEmpty)
    }

    @Test func dates_NilCreatedAtDatedAfterItem_IsBought() {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient)
        let purchaseDate = offset(60)
        let purchase = makePurchase(of: ingredient, on: purchaseDate, savedAt: nil)

        let result = ShoppingListBought.dates(items: [item], purchases: [purchase])

        #expect(result[item.persistentModelID] == purchaseDate)
    }

    @Test func dates_NilCreatedAtDatedAtItemInstant_IsBought() {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient)
        let purchase = makePurchase(of: ingredient, on: created, savedAt: nil)

        #expect(ShoppingListBought.dates(items: [item], purchases: [purchase])[item.persistentModelID] == created)
    }

    @Test func dates_NilCreatedAtDatedBeforeItem_IsNotBought() {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient)
        let purchase = makePurchase(of: ingredient, on: offset(-1), savedAt: nil)

        #expect(ShoppingListBought.dates(items: [item], purchases: [purchase]).isEmpty)
    }

    @Test func dates_UnlinkedItem_IsNeverBought() {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: nil)
        let purchase = makePurchase(of: ingredient, on: offset(60), savedAt: offset(60))

        #expect(ShoppingListBought.dates(items: [item], purchases: [purchase]).isEmpty)
    }

    @Test func dates_SeveralQualifyingPurchases_PicksTheEarliestDate() {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient)
        let earliestDate = offset(-5 * 86_400)
        let purchases = [
            makePurchase(of: ingredient, on: offset(5 * 86_400), savedAt: offset(60)),
            makePurchase(of: ingredient, on: earliestDate, savedAt: offset(120)),
            makePurchase(of: ingredient, on: offset(-9 * 86_400), savedAt: offset(-60)),
            makePurchase(of: ingredient, on: offset(86_400), savedAt: nil)
        ]

        let result = ShoppingListBought.dates(items: [item], purchases: purchases)

        #expect(result[item.persistentModelID] == earliestDate)
    }

    @Test func dates_PurchasesOfOtherIngredients_AreIgnored() {
        let ingredient = makeIngredient()
        let other = makeIngredient("Shea Butter")
        let item = makeItem(ingredient: ingredient)
        let purchase = makePurchase(of: other, on: offset(60), savedAt: offset(60))

        #expect(ShoppingListBought.dates(items: [item], purchases: [purchase]).isEmpty)
    }

    @Test func dates_NoPurchasesOrItems_ReturnsEmpty() {
        let item = makeItem(ingredient: makeIngredient())

        #expect(ShoppingListBought.dates(items: [item], purchases: []).isEmpty)
        #expect(ShoppingListBought.dates(items: [], purchases: []).isEmpty)
    }

    @Test func dates_EachItemUsesItsOwnCreationInstant() {
        let ingredient = makeIngredient()
        let early = makeItem("Early", ingredient: ingredient)
        let late = makeItem("Late", ingredient: ingredient)
        late.createdAt = offset(4 * 86_400)
        let purchase = makePurchase(of: ingredient, on: offset(2 * 86_400), savedAt: offset(2 * 86_400))

        let result = ShoppingListBought.dates(items: [early, late], purchases: [purchase])

        #expect(result[early.persistentModelID] != nil)
        #expect(result[late.persistentModelID] == nil)
    }
}
