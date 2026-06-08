import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("ProviderFormViewModel", .serialized)
@MainActor
struct ProviderFormViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientPurchase.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    @Test func emptyNameInvalid() {
        let model = ProviderFormViewModel()
        #expect(!model.isValid(among: []))
    }

    @Test func duplicateInvalid() {
        let existing = Provider(name: "Acme")
        let model = ProviderFormViewModel()
        model.name = "ACME"
        #expect(model.isDuplicate(among: [existing]))
    }

    @Test func saveInsertsWithTrimmedFields() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let model = ProviderFormViewModel()
        model.name = "  Acme  "
        model.website = "  https://acme.example  "
        model.notes = "  10-day lead  "
        model.save(context: ctx)
        try ctx.save()
        let fetched = try ctx.fetch(FetchDescriptor<Provider>())
        #expect(fetched.first?.name == "Acme")
        #expect(fetched.first?.website == "https://acme.example")
        #expect(fetched.first?.notes == "10-day lead")
    }

    @Test func saveUpdatesExisting() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = Provider(name: "Acme", website: "old", notes: "")
        ctx.insert(existing)
        let model = ProviderFormViewModel(provider: existing)
        model.website = "https://new.example"
        model.save(context: ctx)
        #expect(existing.website == "https://new.example")
    }
}
