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

    private func day(_ offset: Int) throws -> Date {
        try #require(Calendar.current.date(byAdding: .day, value: offset, to: created))
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

    private func makePurchase(of ingredient: Ingredient, on date: Date) -> IngredientPurchase {
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
        context.insert(purchase)
        purchase.attach(to: ingredient)
        return purchase
    }

    @Test func dates_PurchaseAfterCreation_IsBoughtWithThatDate() throws {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient)
        let purchaseDate = try day(2)
        let purchase = makePurchase(of: ingredient, on: purchaseDate)

        let result = ShoppingListBought.dates(items: [item], purchases: [purchase])

        #expect(result[item.persistentModelID] == purchaseDate)
    }

    @Test func dates_PurchaseBeforeCreation_IsNotBought() throws {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient)
        let purchase = makePurchase(of: ingredient, on: try day(-2))

        #expect(ShoppingListBought.dates(items: [item], purchases: [purchase]).isEmpty)
    }

    @Test func dates_PurchaseAtCreationInstant_IsNotBought() {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient)
        let purchase = makePurchase(of: ingredient, on: created)

        #expect(ShoppingListBought.dates(items: [item], purchases: [purchase]).isEmpty)
    }

    @Test func dates_UnlinkedItem_IsNeverBought() throws {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: nil)
        let purchase = makePurchase(of: ingredient, on: try day(2))

        #expect(ShoppingListBought.dates(items: [item], purchases: [purchase]).isEmpty)
    }

    @Test func dates_SeveralQualifyingPurchases_PicksTheEarliest() throws {
        let ingredient = makeIngredient()
        let item = makeItem(ingredient: ingredient)
        let purchases = [
            makePurchase(of: ingredient, on: try day(5)),
            makePurchase(of: ingredient, on: try day(-3)),
            makePurchase(of: ingredient, on: try day(1)),
            makePurchase(of: ingredient, on: try day(9))
        ]

        let result = ShoppingListBought.dates(items: [item], purchases: purchases)

        #expect(result[item.persistentModelID] == (try day(1)))
    }

    @Test func dates_PurchasesOfOtherIngredients_AreIgnored() throws {
        let ingredient = makeIngredient()
        let other = makeIngredient("Shea Butter")
        let item = makeItem(ingredient: ingredient)
        let purchase = makePurchase(of: other, on: try day(2))

        #expect(ShoppingListBought.dates(items: [item], purchases: [purchase]).isEmpty)
    }

    @Test func dates_NoPurchasesOrItems_ReturnsEmpty() {
        let item = makeItem(ingredient: makeIngredient())

        #expect(ShoppingListBought.dates(items: [item], purchases: []).isEmpty)
        #expect(ShoppingListBought.dates(items: [], purchases: []).isEmpty)
    }

    @Test func dates_EachItemUsesItsOwnCreationDate() throws {
        let ingredient = makeIngredient()
        let early = makeItem("Early", ingredient: ingredient)
        let late = makeItem("Late", ingredient: ingredient)
        late.createdAt = try day(4)
        let purchase = makePurchase(of: ingredient, on: try day(2))

        let result = ShoppingListBought.dates(items: [early, late], purchases: [purchase])

        #expect(result[early.persistentModelID] != nil)
        #expect(result[late.persistentModelID] == nil)
    }
}
