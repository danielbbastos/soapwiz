import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Counts the fetches the shopping list rows make.
@MainActor
final class ShoppingListFetchCounter {
    private(set) var count = 0

    func fetch(_ context: ModelContext) throws -> [ShoppingListItem] {
        count += 1
        return try ShoppingListRows.fetchAll(in: context)
    }
}

/// When the shopping list rows refetch, and when they leave the list alone (SW-367).
@Suite("Shopping list rows", .serialized)
@MainActor
struct ShoppingListRowsTests: InventoryRowsTestHelpers {

    private func makeItem(_ name: String, createdAt: Date) -> ShoppingListItem {
        let item = ShoppingListItem(name: name)
        item.createdAt = createdAt
        return item
    }

    @Test func init_FetchesItemsByCreationDate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        context.insert(makeItem("Third", createdAt: base.addingTimeInterval(20)))
        context.insert(makeItem("First", createdAt: base))
        context.insert(makeItem("Second", createdAt: base.addingTimeInterval(10)))
        try context.save()

        let sut = ShoppingListRows(context: context)

        #expect(sut.items.map(\.name) == ["First", "Second", "Third"])
    }

    @Test func save_InsertsItem_RefetchesAndShowsIt() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let counter = ShoppingListFetchCounter()
        let sut = ShoppingListRows(context: context, fetchItems: counter.fetch)
        let fetchesBefore = counter.count

        context.insert(ShoppingListItem(name: "Lye"))
        try context.save()

        #expect(counter.count == fetchesBefore + 1)
        #expect(sut.items.map(\.name) == ["Lye"])
    }

    @Test func save_OnlyIngredient_DoesNotRefetch() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let counter = ShoppingListFetchCounter()
        let sut = ShoppingListRows(context: context, fetchItems: counter.fetch)
        let fetchesBefore = counter.count

        context.insert(Ingredient(name: "Lye", unit: "g"))
        try context.save()

        #expect(counter.count == fetchesBefore)
        #expect(sut.items.isEmpty)
    }

    @Test func prune_ImportRunning_DropsDeletedItemWithoutFetching() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = ShoppingListItem(name: "First")
        let second = ShoppingListItem(name: "Second")
        context.insert(first)
        context.insert(second)
        try context.save()
        let counter = ShoppingListFetchCounter()
        let sut = ShoppingListRows(context: context, pruneInterval: .milliseconds(10), fetchItems: counter.fetch)
        let fetchesBefore = counter.count
        #expect(sut.items.count == 2)

        sut.handle(importStart)
        context.delete(first)
        await waitUntil { sut.items.count == 1 }

        #expect(sut.items.first === second)
        #expect(counter.count == fetchesBefore)
    }

    @Test func save_DeletesItem_RefetchesAndDropsIt() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = ShoppingListItem(name: "Lye")
        context.insert(item)
        try context.save()
        let sut = ShoppingListRows(context: context)
        #expect(sut.items.count == 1)

        context.delete(item)
        try context.save()

        #expect(sut.items.isEmpty)
    }
}
