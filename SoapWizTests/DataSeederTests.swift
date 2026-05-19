import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("DataSeeder", .serialized)
@MainActor
struct DataSeederTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientBatch.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    @Test func seedDoesNotInsertWhenIngredientsExist() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        ctx.insert(Ingredient(name: "Existing"))
        try ctx.save()

        DataSeeder.seedTestIngredients(into: ctx)

        let count = try ctx.fetchCount(FetchDescriptor<Ingredient>())
        #expect(count == 1)
    }
}
