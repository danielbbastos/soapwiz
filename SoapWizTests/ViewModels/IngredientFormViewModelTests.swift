import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("IngredientFormViewModel – save & validation", .serialized)
@MainActor
struct IngredientFormViewModelTests: IngredientFormTestHelpers {

    @Test func emptyNameInvalid() {
        let model = IngredientFormViewModel()
        #expect(!model.isValid)
    }
    @Test func requiresNameAndUnit() {
        let model = IngredientFormViewModel()
        #expect(!model.isValid)
        model.name = "Olive Oil"
        #expect(!model.isValid)
        model.selectedUnit = .grams
        #expect(model.isValid)
    }
    @Test func whitespaceOnlyNameInvalid() {
        let model = IngredientFormViewModel()
        model.name = "   "
        model.selectedUnit = .grams
        #expect(!model.isValid)
    }
    @Test func saveInsertsTrimmedFields() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let cat = IngredientCategory(name: "Oils")
        ctx.insert(cat)

        let model = IngredientFormViewModel()
        model.name = "  Olive Oil  "
        model.selectedUnit = .grams
        model.selectedCategory = cat
        let returned = model.save(context: ctx)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Ingredient>())
        #expect(fetched.first?.name == "Olive Oil")
        #expect(fetched.first?.unit == "g")
        #expect(fetched.first?.category === cat)
        #expect(returned === fetched.first)
    }
    @Test func saveUpdatesExisting() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = Ingredient(name: "Olive Oil")
        ctx.insert(existing)

        let model = IngredientFormViewModel(ingredient: existing)
        model.name = "Coconut Oil"
        let returned = model.save(context: ctx)
        #expect(existing.name == "Coconut Oil")
        #expect(returned == nil)
    }
    @Test func saveStoresThreshold() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let model = IngredientFormViewModel()
        model.name = "Olive Oil"
        model.selectedUnit = .grams
        model.lowStockThreshold = "100"
        let ingredient = model.save(context: ctx)
        #expect(ingredient?.lowStockThreshold == 100)
    }
    @Test func saveClearsThresholdWhenEmpty() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = Ingredient(name: "Olive Oil")
        existing.lowStockThreshold = 50
        ctx.insert(existing)

        let model = IngredientFormViewModel(ingredient: existing)
        model.lowStockThreshold = ""
        model.save(context: ctx)
        #expect(existing.lowStockThreshold == nil)
    }
    @Test func populatesThresholdWhenEditing() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = Ingredient(name: "Olive Oil")
        existing.lowStockThreshold = 75.5
        ctx.insert(existing)

        let model = IngredientFormViewModel(ingredient: existing)
        let parsed = Double(model.lowStockThreshold.replacingOccurrences(of: ",", with: "."))
        #expect(parsed == 75.5)
    }
}
