import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("QuantityUnitFormViewModel")
@MainActor
struct QuantityUnitFormViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientBatch.self, IngredientCategory.self, QuantityUnit.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    @Test func emptyNameInvalid() {
        let model = QuantityUnitFormViewModel()
        #expect(!model.isValid(among: []))
    }

    @Test func emptySymbolInvalid() {
        let model = QuantityUnitFormViewModel()
        model.name = "Gram"
        #expect(!model.isValid(among: []))
    }

    @Test func whitespaceOnlyInvalid() {
        let model = QuantityUnitFormViewModel()
        model.name = "   "
        model.symbol = "   "
        #expect(!model.isValid(among: []))
    }

    @Test func duplicateNameInvalidCaseInsensitive() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = QuantityUnit(name: "Gram", symbol: "g")
        ctx.insert(existing)

        let model = QuantityUnitFormViewModel()
        model.name = "gram"
        model.symbol = "x"
        #expect(model.isDuplicateName(among: [existing]))
        #expect(!model.isValid(among: [existing]))
    }

    @Test func duplicateSymbolInvalidCaseInsensitive() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = QuantityUnit(name: "Gram", symbol: "g")
        ctx.insert(existing)

        let model = QuantityUnitFormViewModel()
        model.name = "Gramo"
        model.symbol = "G"
        #expect(model.isDuplicateSymbol(among: [existing]))
        #expect(!model.isValid(among: [existing]))
    }

    @Test func editingSelfIsNotDuplicate() {
        let existing = QuantityUnit(name: "Gram", symbol: "g")
        let model = QuantityUnitFormViewModel(unit: existing)
        #expect(!model.isDuplicateName(among: [existing]))
        #expect(!model.isDuplicateSymbol(among: [existing]))
        #expect(model.isValid(among: [existing]))
    }

    @Test func saveInsertsNewUnit() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let model = QuantityUnitFormViewModel()
        model.name = "  Gram  "
        model.symbol = "  g  "
        model.save(context: ctx)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<QuantityUnit>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Gram")
        #expect(fetched.first?.symbol == "g")
    }

    @Test func saveUpdatesExistingUnit() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = QuantityUnit(name: "Gram", symbol: "g")
        ctx.insert(existing)

        let model = QuantityUnitFormViewModel(unit: existing)
        model.name = "Kilogram"
        model.symbol = "kg"
        model.save(context: ctx)
        #expect(existing.name == "Kilogram")
        #expect(existing.symbol == "kg")
    }
}
