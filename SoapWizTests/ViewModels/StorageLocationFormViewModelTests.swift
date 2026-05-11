import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("StorageLocationFormViewModel")
@MainActor
struct StorageLocationFormViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientBatch.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    @Test func emptyNameInvalid() {
        let model = StorageLocationFormViewModel()
        #expect(!model.isValid(among: []))
    }

    @Test func duplicateInvalid() {
        let existing = StorageLocation(name: "Shelf A")
        let model = StorageLocationFormViewModel()
        model.name = "shelf a"
        #expect(model.isDuplicate(among: [existing]))
    }

    @Test func saveInserts() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let model = StorageLocationFormViewModel()
        model.name = "Shelf A"
        model.locationDescription = "Cool"
        model.save(context: ctx)
        try ctx.save()
        let fetched = try ctx.fetch(FetchDescriptor<StorageLocation>())
        #expect(fetched.first?.name == "Shelf A")
        #expect(fetched.first?.locationDescription == "Cool")
    }

    @Test func saveUpdates() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = StorageLocation(name: "Shelf A", locationDescription: "old")
        ctx.insert(existing)
        let model = StorageLocationFormViewModel(location: existing)
        model.locationDescription = "new"
        model.save(context: ctx)
        #expect(existing.locationDescription == "new")
    }
}
