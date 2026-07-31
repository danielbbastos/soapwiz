import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("ProviderFormViewModel", .serialized)
@MainActor
struct ProviderFormViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientPurchase.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
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

    /// Must match `DuplicateMerger`'s notion of the same name, or the merger will
    /// collapse a pair the form allowed.
    @Test func duplicateInvalidIgnoringDiacriticsAndSpacing() {
        let existing = Provider(name: "Sabão  Supply")
        let model = ProviderFormViewModel()
        model.name = "Sabao Supply"
        #expect(model.isDuplicate(among: [existing]))
    }

    @Test func distinctNameIsNotDuplicate() {
        let existing = Provider(name: "Acme")
        let model = ProviderFormViewModel()
        model.name = "Globex"
        #expect(!model.isDuplicate(among: [existing]))
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

    @Test func save_NewProvider_ReturnsInsertedProvider() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let model = ProviderFormViewModel()
        model.name = "  Acme  "
        let saved = model.save(context: ctx)
        #expect(saved.name == "Acme")
    }

    @Test func save_EditingProvider_ReturnsSameProvider() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = Provider(name: "Acme", website: "old", notes: "")
        ctx.insert(existing)
        let model = ProviderFormViewModel(provider: existing)
        model.website = "https://new.example"
        let saved = model.save(context: ctx)
        #expect(saved === existing)
    }
}
