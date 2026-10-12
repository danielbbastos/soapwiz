import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The categories list `InventoryRows` keeps beside the ingredients and purchases (SW-221).
@Suite("Inventory rows categories", .serialized)
@MainActor
struct InventoryRowsCategoryTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = ModelContainerFactory.schema
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
    }

    @Test func init_LoadsCategoriesSortedByName() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(IngredientCategory(name: "Oils"))
        context.insert(IngredientCategory(name: "Butters"))
        context.insert(IngredientCategory(name: "Lyes"))
        try context.save()

        let sut = InventoryRows(context: context)

        #expect(sut.categories.map(\.name) == ["Butters", "Lyes", "Oils"])
    }

    @Test func init_EmptyStore_HasNoCategories() throws {
        let container = try makeContainer()

        let sut = InventoryRows(context: container.mainContext)

        #expect(sut.categories.isEmpty)
    }

    @Test func save_InOwnContext_InsertingCategory_RefreshesCategories() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(IngredientCategory(name: "Oils"))
        try context.save()
        let sut = InventoryRows(context: context)

        context.insert(IngredientCategory(name: "Butters"))
        try context.save()

        #expect(sut.categories.map(\.name) == ["Butters", "Oils"])
    }

    @Test func save_InOwnContext_RenamingCategory_ResortsCategories() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let oils = IngredientCategory(name: "Oils")
        context.insert(oils)
        context.insert(IngredientCategory(name: "Lyes"))
        try context.save()
        let sut = InventoryRows(context: context)
        #expect(sut.categories.map(\.name) == ["Lyes", "Oils"])

        oils.name = "Acids"
        try context.save()

        #expect(sut.categories.map(\.name) == ["Acids", "Lyes"])
    }

    @Test func save_InOwnContext_DeletingCategory_DropsIt() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let oils = IngredientCategory(name: "Oils")
        context.insert(oils)
        context.insert(IngredientCategory(name: "Lyes"))
        try context.save()
        let sut = InventoryRows(context: context)

        context.delete(oils)
        try context.save()

        #expect(sut.categories.map(\.name) == ["Lyes"])
        #expect(sut.categories.allSatisfy { !$0.isDeleted && $0.modelContext != nil })
    }
}
