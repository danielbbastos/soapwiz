import Testing
import Foundation
import SwiftData
@testable import SoapWiz

private struct LinkedShoppingItem {
    let item: ShoppingListItem
    let id: PersistentIdentifier
}

@Suite("Shopping list text")
@MainActor
struct ShoppingListTextTests {

    private let locale = Locale(identifier: "en_US_POSIX")
    private let title = String(localized: "Shopping list")

    private func item(
        _ name: String,
        amount: Double? = nil,
        unit: String = "",
        note: String = "",
        createdAt: Date = Date(timeIntervalSince1970: 1_000),
        isChecked: Bool = false
    ) -> ShoppingListItem {
        let item = ShoppingListItem(name: name, amount: amount, unit: unit, note: note)
        item.createdAt = createdAt
        item.isChecked = isChecked
        return item
    }

    @Test func make_NoItems_ReturnsEmpty() {
        #expect(ShoppingListText.make(items: [], locale: locale) == "")
    }

    @Test func make_OnlyCheckedItems_ReturnsEmpty() {
        let items = [item("Lye", isChecked: true)]

        #expect(ShoppingListText.make(items: items, locale: locale) == "")
    }

    @Test func make_AmountAndUnit_AreListedAfterName() {
        let items = [item("Olive oil", amount: 1.5, unit: "kg")]

        #expect(ShoppingListText.make(items: items, locale: locale) == "\(title)\n• Olive oil, 1.5 kg")
    }

    @Test func make_NoAmount_OmitsAmountPart() {
        let items = [item("Beeswax", unit: "g")]

        #expect(ShoppingListText.make(items: items, locale: locale) == "\(title)\n• Beeswax")
    }

    @Test func make_AmountWithoutUnit_ShowsNumberOnly() {
        let items = [item("Moulds", amount: 4)]

        #expect(ShoppingListText.make(items: items, locale: locale) == "\(title)\n• Moulds, 4")
    }

    @Test func make_Note_IsAppendedInParentheses() {
        let items = [
            item("Lye", amount: 500, unit: "g", note: "food grade"),
            item("Labels", note: "kraft paper")
        ]

        #expect(
            ShoppingListText.make(items: items, locale: locale)
                == "\(title)\n• Lye, 500 g (food grade)\n• Labels (kraft paper)"
        )
    }

    @Test func make_Items_AreOrderedByCreationDate() {
        let items = [
            item("Second", createdAt: Date(timeIntervalSince1970: 2_000)),
            item("First", createdAt: Date(timeIntervalSince1970: 1_000))
        ]

        #expect(ShoppingListText.make(items: items, locale: locale) == "\(title)\n• First\n• Second")
    }

    @Test func make_CheckedItems_AreExcluded() {
        let items = [item("Bought", isChecked: true), item("Needed")]

        #expect(ShoppingListText.make(items: items, locale: locale) == "\(title)\n• Needed")
    }

    private let currencyCode = "EUR"
    private let purchase = LastPurchase(quantity: 1, supplierName: "Supplier", pricePerUnit: 12)

    private func linkedItem(
        _ name: String,
        amount: Double? = nil,
        unit: String = "",
        note: String = "",
        isChecked: Bool = false,
        in context: ModelContext
    ) -> LinkedShoppingItem {
        let ingredient = Ingredient(name: name, unit: "kg")
        context.insert(ingredient)
        let item = item(name, amount: amount, unit: unit, note: note, isChecked: isChecked)
        context.insert(item)
        item.ingredient = ingredient
        return LinkedShoppingItem(item: item, id: ingredient.persistentModelID)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = ModelContainerFactory.schema
        return try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
    }

    @Test func make_NoLastPurchases_LeavesLinkedItemUnchanged() throws {
        let container = try makeContainer()
        let linked = linkedItem("Olive Oil", amount: 1.5, unit: "kg", in: container.mainContext)

        let text = ShoppingListText.make(items: [linked.item], currencyCode: currencyCode, locale: locale)

        #expect(text == "\(title)\n• Olive Oil, 1.5 kg")
    }

    @Test func make_LastPurchases_PutsDetailsOnIndentedSubLine() throws {
        let container = try makeContainer()
        let linked = linkedItem("Olive Oil", in: container.mainContext)
        let details = try #require(purchase.line(unit: "kg", currencyCode: currencyCode, locale: locale))

        let text = ShoppingListText.make(
            items: [linked.item],
            lastPurchases: [linked.id: purchase],
            currencyCode: currencyCode,
            locale: locale
        )

        #expect(text == "\(title)\n• Olive Oil\n    - \(details)")
    }

    @Test func make_LastPurchases_KeepsAmountAndNoteOnMainLine() throws {
        let container = try makeContainer()
        let linked = linkedItem("Olive Oil", amount: 1.5, unit: "kg", note: "the big tin", in: container.mainContext)
        let details = try #require(purchase.line(unit: "kg", currencyCode: currencyCode, locale: locale))

        let text = ShoppingListText.make(
            items: [linked.item],
            lastPurchases: [linked.id: purchase],
            currencyCode: currencyCode,
            locale: locale
        )

        #expect(text == "\(title)\n• Olive Oil, 1.5 kg (the big tin)\n    - \(details)")
    }

    @Test func make_LastPurchases_LeavesUnlinkedItemUnchanged() throws {
        let container = try makeContainer()
        let linked = linkedItem("Olive Oil", in: container.mainContext)
        let details = try #require(purchase.line(unit: "kg", currencyCode: currencyCode, locale: locale))
        let unlinked = item("Moulds", amount: 4, createdAt: Date(timeIntervalSince1970: 2_000))

        let text = ShoppingListText.make(
            items: [linked.item, unlinked],
            lastPurchases: [linked.id: purchase],
            currencyCode: currencyCode,
            locale: locale
        )

        #expect(text == "\(title)\n• Olive Oil\n    - \(details)\n• Moulds, 4")
    }

    @Test func make_LastPurchases_LeavesLinkedItemWithoutDataUnchanged() throws {
        let container = try makeContainer()
        let withData = linkedItem("Olive Oil", in: container.mainContext)
        let withoutData = linkedItem("Shea Butter", in: container.mainContext)
        withoutData.item.createdAt = Date(timeIntervalSince1970: 2_000)
        let empty = LastPurchase(quantity: nil, supplierName: nil, pricePerUnit: nil)
        let details = try #require(purchase.line(unit: "kg", currencyCode: currencyCode, locale: locale))

        let text = ShoppingListText.make(
            items: [withData.item, withoutData.item],
            lastPurchases: [withData.id: purchase, withoutData.id: empty],
            currencyCode: currencyCode,
            locale: locale
        )

        #expect(text == "\(title)\n• Olive Oil\n    - \(details)\n• Shea Butter")
    }

    @Test func make_LastPurchases_CheckedItemsStayExcluded() throws {
        let container = try makeContainer()
        let checked = linkedItem("Olive Oil", isChecked: true, in: container.mainContext)

        let text = ShoppingListText.make(
            items: [checked.item],
            lastPurchases: [checked.id: purchase],
            currencyCode: currencyCode,
            locale: locale
        )

        #expect(text == "")
    }

    @Test func make_BoughtItems_AreExcluded() throws {
        let container = try makeContainer()
        let bought = linkedItem("Olive Oil", in: container.mainContext)
        let pending = linkedItem("Shea Butter", in: container.mainContext)
        pending.item.createdAt = Date(timeIntervalSince1970: 2_000)

        let text = ShoppingListText.make(
            items: [bought.item, pending.item],
            boughtDates: [bought.item.persistentModelID: Date(timeIntervalSince1970: 3_000)],
            currencyCode: currencyCode,
            locale: locale
        )

        #expect(text == "\(title)\n• Shea Butter")
    }

    @Test func make_NonDefaultLocale_FormatsMainLineAndSubLineQuantity() throws {
        let container = try makeContainer()
        let linked = linkedItem("Olive Oil", amount: 1.5, unit: "kg", in: container.mainContext)
        let german = Locale(identifier: "de_DE")
        let last = LastPurchase(quantity: 2.5, supplierName: nil, pricePerUnit: nil)
        let number = 1.5.formatted(.number.precision(.fractionLength(0...2)).locale(german))
        let subNumber = 2.5.formatted(.number.precision(.fractionLength(0...2)).locale(german))

        let text = ShoppingListText.make(
            items: [linked.item],
            lastPurchases: [linked.id: last],
            currencyCode: currencyCode,
            locale: german
        )

        #expect(text.contains("• Olive Oil, \(number) kg"))
        #expect(text.contains("\(subNumber) kg"))
        #expect(number != "1.5")
    }

    @Test func make_OnlyBoughtItems_ReturnsEmpty() throws {
        let container = try makeContainer()
        let bought = linkedItem("Olive Oil", in: container.mainContext)

        let text = ShoppingListText.make(
            items: [bought.item],
            boughtDates: [bought.item.persistentModelID: Date(timeIntervalSince1970: 3_000)],
            currencyCode: currencyCode,
            locale: locale
        )

        #expect(text == "")
    }
}
