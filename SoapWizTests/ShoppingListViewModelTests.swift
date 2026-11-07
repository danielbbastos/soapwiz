import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Shopping list view model")
@MainActor
struct ShoppingListViewModelTests {

    private let container: ModelContainer
    private let context: ModelContext
    private let now: Date
    private let sut: ShoppingListViewModel

    init() throws {
        let schema = ModelContainerFactory.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        context = container.mainContext
        let fixedNow = try #require(
            Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))
        )
        now = fixedNow
        sut = ShoppingListViewModel(modelContext: context, now: { fixedNow })
    }

    private func makeOutOfStockIngredient(_ name: String = "Olive Oil") -> Ingredient {
        let ingredient = Ingredient(name: name, unit: "g")
        context.insert(ingredient)
        let purchase = IngredientPurchase(
            provider: nil,
            dateOfPurchase: now.addingTimeInterval(-86_400),
            quantity: 1000,
            totalPrice: 10,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        purchase.remainingAmount = 0
        context.insert(purchase)
        purchase.attach(to: ingredient)
        return ingredient
    }

    private func allItems() throws -> [ShoppingListItem] {
        try context.fetch(FetchDescriptor<ShoppingListItem>())
    }

    private func suggestions(_ ingredients: [Ingredient], items: [ShoppingListItem]) throws -> [ShoppingSuggestion] {
        sut.suggestions(
            items: items,
            ingredients: ingredients,
            purchases: try context.fetch(FetchDescriptor<IngredientPurchase>()),
            tracksInventory: true
        )
    }

    @Test func add_Suggestion_CreatesLinkedItemAndHidesSuggestion() throws {
        let ingredient = makeOutOfStockIngredient()
        let suggestion = try #require(try suggestions([ingredient], items: []).first)

        sut.add(suggestion)

        let items = try allItems()
        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.name == "Olive Oil")
        #expect(item.unit == "g")
        #expect(item.amount == nil)
        #expect(item.ingredient === ingredient)
        #expect(try suggestions([ingredient], items: items).isEmpty)
    }

    @Test func addAll_CreatesOneLinkedItemPerSuggestion() throws {
        let first = makeOutOfStockIngredient("Olive Oil")
        let second = makeOutOfStockIngredient("Coconut Oil")
        let all = try suggestions([first, second], items: [])
        #expect(all.count == 2)

        sut.addAll(all)

        let items = try allItems()
        #expect(items.count == 2)
        #expect(Set(items.compactMap { $0.ingredient?.name }) == ["Olive Oil", "Coconut Oil"])
        #expect(try suggestions([first, second], items: items).isEmpty)
    }

    @Test func addAll_NoSuggestions_CreatesNothing() throws {
        sut.addAll([])

        #expect(try allItems().isEmpty)
    }

    @Test func suggestions_CheckedItem_StillSuppressesSuggestion() throws {
        let ingredient = makeOutOfStockIngredient()
        let suggestion = try #require(try suggestions([ingredient], items: []).first)
        sut.add(suggestion)
        let item = try #require(try allItems().first)

        sut.toggle(item)

        #expect(try suggestions([ingredient], items: try allItems()).isEmpty)
    }

    @Test func addItem_TrimsNameAndNote() throws {
        sut.addItem(name: "  Lye  ", amount: 500, unit: "g", ingredient: nil, note: " food grade ")

        let item = try #require(try allItems().first)
        #expect(item.name == "Lye")
        #expect(item.note == "food grade")
        #expect(item.amount == 500)
        #expect(item.unit == "g")
    }

    @Test func addItem_BlankName_IsIgnored() throws {
        sut.addItem(name: "   ", amount: nil, unit: "", ingredient: nil, note: "")

        #expect(try allItems().isEmpty)
    }

    @Test func update_ChangesFieldsAndLink() throws {
        let ingredient = Ingredient(name: "Shea Butter", unit: "kg")
        context.insert(ingredient)
        sut.addItem(name: "Butter", amount: nil, unit: "", ingredient: nil, note: "")
        let item = try #require(try allItems().first)

        sut.update(item, name: " Shea ", amount: 2, unit: "kg", ingredient: ingredient, note: "raw")

        #expect(item.name == "Shea")
        #expect(item.amount == 2)
        #expect(item.unit == "kg")
        #expect(item.ingredient === ingredient)
        #expect(item.ingredientSlug == ingredient.librarySlug)
        #expect(item.note == "raw")
    }

    @Test func update_ChangingLink_ResetsCreatedAt() throws {
        let ingredient = Ingredient(name: "Shea Butter", unit: "kg")
        context.insert(ingredient)
        sut.addItem(name: "Butter", amount: nil, unit: "", ingredient: nil, note: "")
        let item = try #require(try allItems().first)
        item.createdAt = Date(timeIntervalSince1970: 1_000)

        sut.update(item, name: "Butter", amount: nil, unit: "", ingredient: ingredient, note: "")
        #expect(item.createdAt == now)

        item.createdAt = Date(timeIntervalSince1970: 1_000)
        sut.update(item, name: "Butter", amount: nil, unit: "", ingredient: nil, note: "")
        #expect(item.createdAt == now)
    }

    @Test func update_SameLink_KeepsCreatedAt() throws {
        let ingredient = Ingredient(name: "Shea Butter", unit: "kg")
        context.insert(ingredient)
        sut.addItem(name: "Butter", amount: nil, unit: "", ingredient: ingredient, note: "")
        let item = try #require(try allItems().first)
        let original = Date(timeIntervalSince1970: 1_000)
        item.createdAt = original

        sut.update(item, name: "Butter 2", amount: 3, unit: "kg", ingredient: ingredient, note: "raw")

        #expect(item.createdAt == original)
    }

    @Test func update_LinkingToIngredientBoughtSinceCreation_IsNotBought() throws {
        let ingredient = Ingredient(name: "Shea Butter", unit: "kg")
        context.insert(ingredient)
        sut.addItem(name: "Butter", amount: nil, unit: "", ingredient: nil, note: "")
        let item = try #require(try allItems().first)
        let purchaseDate = try #require(Calendar.current.date(byAdding: .day, value: -3, to: now))
        item.createdAt = try #require(Calendar.current.date(byAdding: .day, value: -10, to: now))
        let purchase = IngredientPurchase(
            provider: nil,
            dateOfPurchase: purchaseDate,
            quantity: 100,
            totalPrice: 10,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        context.insert(purchase)
        purchase.attach(to: ingredient)

        sut.update(item, name: "Butter", amount: nil, unit: "", ingredient: ingredient, note: "")

        #expect(ShoppingListBought.dates(items: [item], purchases: [purchase]).isEmpty)
    }

    @Test func update_BlankName_LeavesItemUnchanged() throws {
        sut.addItem(name: "Lye", amount: 1, unit: "kg", ingredient: nil, note: "")
        let item = try #require(try allItems().first)

        sut.update(item, name: " ", amount: 9, unit: "g", ingredient: nil, note: "x")

        #expect(item.name == "Lye")
        #expect(item.amount == 1)
    }

    @Test func update_UnlinkingClearsIngredientAndSlug() throws {
        let ingredient = Ingredient(name: "Lye", unit: "g")
        context.insert(ingredient)
        sut.addItem(name: "Lye", amount: nil, unit: "g", ingredient: ingredient, note: "")
        let item = try #require(try allItems().first)

        sut.update(item, name: "Lye", amount: nil, unit: "g", ingredient: nil, note: "")

        #expect(item.ingredient == nil)
        #expect(item.ingredientSlug.isEmpty)
    }

    @Test func toggle_SetsAndClearsCheckedAt() throws {
        sut.addItem(name: "Lye", amount: nil, unit: "", ingredient: nil, note: "")
        let item = try #require(try allItems().first)

        sut.toggle(item)
        #expect(item.isChecked)
        #expect(item.checkedAt == now)

        sut.toggle(item)
        #expect(!item.isChecked)
        #expect(item.checkedAt == nil)
    }

    @Test func clearChecked_DeletesOnlyCheckedItems() throws {
        sut.addItem(name: "A", amount: nil, unit: "", ingredient: nil, note: "")
        sut.addItem(name: "B", amount: nil, unit: "", ingredient: nil, note: "")
        let items = try allItems()
        let first = try #require(items.first { $0.name == "A" })
        sut.toggle(first)

        sut.clearChecked(in: items)

        let remaining = try allItems()
        #expect(remaining.map(\.name) == ["B"])
    }

    @Test func clearChecked_BoughtItems_AreDeletedToo() throws {
        sut.addItem(name: "A", amount: nil, unit: "", ingredient: nil, note: "")
        sut.addItem(name: "B", amount: nil, unit: "", ingredient: nil, note: "")
        sut.addItem(name: "C", amount: nil, unit: "", ingredient: nil, note: "")
        let items = try allItems()
        let checked = try #require(items.first { $0.name == "A" })
        let bought = try #require(items.first { $0.name == "B" })
        sut.toggle(checked)

        sut.clearChecked(in: items, boughtDates: [bought.persistentModelID: now])

        #expect(try allItems().map(\.name) == ["C"])
    }

    @Test func removeAll_DeletesEveryGivenItem() throws {
        sut.addItem(name: "A", amount: nil, unit: "", ingredient: nil, note: "")
        sut.addItem(name: "B", amount: nil, unit: "", ingredient: nil, note: "")
        sut.addItem(name: "C", amount: nil, unit: "", ingredient: nil, note: "")
        let items = try allItems()
        let kept = try #require(items.first { $0.name == "C" })

        sut.removeAll(items.filter { $0 !== kept })

        #expect(try allItems().map(\.name) == ["C"])
    }

    @Test func removeAll_NoItems_ChangesNothing() throws {
        sut.addItem(name: "A", amount: nil, unit: "", ingredient: nil, note: "")

        sut.removeAll([])

        #expect(try allItems().count == 1)
    }

    @Test func delete_RemovesItem() throws {
        sut.addItem(name: "A", amount: nil, unit: "", ingredient: nil, note: "")
        let item = try #require(try allItems().first)

        sut.delete(item)

        #expect(try allItems().isEmpty)
    }

    @Test func dismiss_SetsDateAndHidesSuggestion() throws {
        let ingredient = makeOutOfStockIngredient()
        let suggestion = try #require(try suggestions([ingredient], items: []).first)

        sut.dismiss(suggestion)

        #expect(ingredient.shoppingSuggestionDismissedAt == now)
        #expect(try suggestions([ingredient], items: []).isEmpty)
    }
}
