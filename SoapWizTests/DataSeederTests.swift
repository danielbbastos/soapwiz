import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("DataSeeder")
@MainActor
struct DataSeederTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientBatch.self, IngredientCategory.self, QuantityUnit.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    private let defaultSeeds: [DataSeeder.QuantityUnitSeed] = [
        .init(name: "Gram", symbol: "g"),
        .init(name: "Kilogram", symbol: "kg")
    ]

    @Test func seedsUnitsIntoEmptyStore() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        DataSeeder.seedQuantityUnits(defaultSeeds, into: ctx)
        try ctx.save()

        let units = try ctx.fetch(FetchDescriptor<QuantityUnit>(sortBy: [SortDescriptor(\.name)]))
        #expect(units.count == 2)
        #expect(units[0].name == "Gram" && units[0].symbol == "g")
        #expect(units[1].name == "Kilogram" && units[1].symbol == "kg")
    }

    @Test func doesNotSeedWhenUnitsAlreadyExist() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        ctx.insert(QuantityUnit(name: "Existing", symbol: "ex"))
        try ctx.save()

        DataSeeder.seedQuantityUnits(defaultSeeds, into: ctx)
        try ctx.save()

        let units = try ctx.fetch(FetchDescriptor<QuantityUnit>())
        #expect(units.count == 1)
        #expect(units.first?.name == "Existing")
    }

    @Test func emptySeeds_producesNoUnits() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        DataSeeder.seedQuantityUnits([], into: ctx)
        try ctx.save()

        let units = try ctx.fetch(FetchDescriptor<QuantityUnit>())
        #expect(units.isEmpty)
    }
}
