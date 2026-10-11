import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// What the store's persistent history reports to a consumer asking for the
/// changes since its last look (SW-221).
@Suite("Store history cursor", .serialized)
@MainActor
struct StoreHistoryCursorTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = ModelContainerFactory.schema
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
    }

    @Test func changes_MadeBeforeCursorExisted_AreNotReported() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(Ingredient(name: "Olive Oil", unit: "g"))
        try context.save()

        let sut = StoreHistoryCursor(context: context)

        #expect(try sut.changesSinceLastCheck().isEmpty)
    }

    @Test func changes_SavedAfterCursorExisted_AreReported() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let sut = StoreHistoryCursor(context: context)

        context.insert(Ingredient(name: "Olive Oil", unit: "g"))
        try context.save()

        let names = try sut.changesSinceLastCheck().map(\.entityName)
        #expect(names.contains(Schema.entityName(for: Ingredient.self)))
    }

    @Test func changes_AreReportedOnce() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let sut = StoreHistoryCursor(context: context)
        context.insert(Ingredient(name: "Olive Oil", unit: "g"))
        try context.save()
        _ = try sut.changesSinceLastCheck()

        #expect(try sut.changesSinceLastCheck().isEmpty)
    }

    @Test func changes_SavedAfterAnEarlierCheck_AreReportedAlone() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let sut = StoreHistoryCursor(context: context)
        context.insert(Ingredient(name: "Olive Oil", unit: "g"))
        try context.save()
        _ = try sut.changesSinceLastCheck()

        context.insert(IngredientCategory(name: "Oils"))
        try context.save()

        let names = Set(try sut.changesSinceLastCheck().map(\.entityName))
        #expect(names == [Schema.entityName(for: IngredientCategory.self)])
    }

    @Test func changes_FromAnotherContext_AreReported() throws {
        let container = try makeContainer()
        let sut = StoreHistoryCursor(context: container.mainContext)
        let other = ModelContext(container)

        other.insert(Provider(name: "Soap Supply"))
        try other.save()

        let names = try sut.changesSinceLastCheck().map(\.entityName)
        #expect(names.contains(Schema.entityName(for: Provider.self)))
    }
}
