import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("QuantityUnitListViewModel", .serialized)
@MainActor
struct QuantityUnitListViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientBatch.self, IngredientCategory.self, QuantityUnit.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    @Test func deleteSucceedsWhenNoIngredients() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let unit = QuantityUnit(name: "Gram", symbol: "g")
        ctx.insert(unit)
        try ctx.save()

        let model = QuantityUnitListViewModel()
        model.delete(at: IndexSet(integer: 0), in: [unit], context: ctx)
        try ctx.save()
        #expect(model.deleteBlockedUnit == nil)

        let remaining = try ctx.fetch(FetchDescriptor<QuantityUnit>())
        #expect(remaining.isEmpty)
    }

    @Test func deleteBlockedWhenIngredientsAssigned() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let unit = QuantityUnit(name: "Gram", symbol: "g")
        ctx.insert(unit)
        let ingredient = Ingredient(name: "Olive Oil", unit: unit)
        ctx.insert(ingredient)
        try ctx.save()

        let model = QuantityUnitListViewModel()
        model.delete(at: IndexSet(integer: 0), in: [unit], context: ctx)
        #expect(model.deleteBlockedUnit === unit)

        let remaining = try ctx.fetch(FetchDescriptor<QuantityUnit>())
        #expect(remaining.count == 1)
    }
}
