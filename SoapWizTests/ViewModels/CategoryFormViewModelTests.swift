import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("CategoryFormViewModel", .serialized)
@MainActor
struct CategoryFormViewModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientPurchase.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
    }

    @Test func emptyNameInvalid() throws {
        let model = CategoryFormViewModel()
        #expect(!model.isValid(among: []))
    }

    @Test func whitespaceOnlyInvalid() throws {
        let model = CategoryFormViewModel()
        model.name = "   "
        #expect(!model.isValid(among: []))
    }

    @Test func duplicateNameInvalidCaseInsensitive() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = IngredientCategory(name: "Oils")
        ctx.insert(existing)
        let model = CategoryFormViewModel()
        model.name = "oils"
        #expect(model.isDuplicate(among: [existing]))
        #expect(!model.isValid(among: [existing]))
    }

    /// The validator has to agree with `DuplicateMerger` about what counts as the
    /// same name, or a user can deliberately create a pair the merger then
    /// silently collapses.
    @Test func duplicateNameInvalidIgnoringDiacritics() throws {
        let existing = IngredientCategory(name: "Óleos")
        let model = CategoryFormViewModel()
        model.name = "Oleos"
        #expect(model.isDuplicate(among: [existing]))
    }

    @Test func duplicateNameInvalidIgnoringInternalWhitespace() throws {
        let existing = IngredientCategory(name: "Olive Oil")
        let model = CategoryFormViewModel()
        model.name = "Olive  Oil"
        #expect(model.isDuplicate(among: [existing]))
    }

    /// Stored names are not trimmed on every path — seeded and restored rows keep
    /// whatever they were given — so the stored side must be normalised too.
    @Test func duplicateNameInvalidWhenStoredNameIsUntrimmed() throws {
        let existing = IngredientCategory(name: "  Oils  ")
        let model = CategoryFormViewModel()
        model.name = "Oils"
        #expect(model.isDuplicate(among: [existing]))
    }

    @Test func distinctNameIsNotDuplicate() throws {
        let existing = IngredientCategory(name: "Oils")
        let model = CategoryFormViewModel()
        model.name = "Waxes"
        #expect(!model.isDuplicate(among: [existing]))
        #expect(model.isValid(among: [existing]))
    }

    @Test func editingSelfIsNotDuplicate() throws {
        let existing = IngredientCategory(name: "Oils")
        let model = CategoryFormViewModel(category: existing)
        #expect(!model.isDuplicate(among: [existing]))
        #expect(model.isValid(among: [existing]))
    }

    @Test func saveInsertsNewCategory() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let model = CategoryFormViewModel()
        model.name = "  Oils  "
        model.save(context: ctx)
        try ctx.save()
        let fetched = try ctx.fetch(FetchDescriptor<IngredientCategory>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Oils")
    }

    @Test func saveUpdatesExistingCategory() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = IngredientCategory(name: "Clays")
        ctx.insert(existing)
        let model = CategoryFormViewModel(category: existing)
        model.name = "Cosmetic Clays"
        model.save(context: ctx)
        #expect(existing.name == "Cosmetic Clays")
    }

    @Test func save_EditingOthers_Renames() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = IngredientCategory(name: IngredientCategory.Name.others)
        ctx.insert(existing)
        let model = CategoryFormViewModel(category: existing)
        model.name = "Miscellaneous"
        model.save(context: ctx)
        #expect(existing.name == "Miscellaneous")
    }

    @Test(arguments: IngredientCategory.Name.all.filter { $0 != IngredientCategory.Name.others })
    func save_EditingLockedBuiltIn_KeepsName(name: String) throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = IngredientCategory(name: name)
        ctx.insert(existing)
        let model = CategoryFormViewModel(category: existing)
        model.name = "Renamed"
        let saved = model.save(context: ctx)
        #expect(saved === existing)
        #expect(existing.name == name)
    }

    @Test func save_NewCategory_ReturnsInsertedCategory() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let model = CategoryFormViewModel()
        model.name = "  Oils  "
        let saved = model.save(context: ctx)
        #expect(saved.name == "Oils")
    }

    @Test func save_EditingCategory_ReturnsSameCategory() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = IngredientCategory(name: "Clays")
        ctx.insert(existing)
        let model = CategoryFormViewModel(category: existing)
        model.name = "Cosmetic Clays"
        let saved = model.save(context: ctx)
        #expect(saved === existing)
    }
}
