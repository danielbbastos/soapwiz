import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("IngredientChemistry", .serialized)
@MainActor
struct IngredientChemistryTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Ingredient.self, IngredientPurchase.self, IngredientCategory.self, StorageLocation.self, Provider.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
    }

    @Test func oilWithProfile_HasStatsAndProfile() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let category = IngredientCategory(name: IngredientCategory.Name.oils)
        let oil = Ingredient.mockOil(name: "Olive", naohSap: 0.134, palmitic: 14, oleic: 69)
        oil.category = category
        ctx.insert(category)
        ctx.insert(oil)

        let sut = IngredientChemistry(ingredient: oil)
        let stats = try #require(sut.stats)

        #expect(sut.showsChemistry)
        #expect(sut.hasFattyAcidProfile)
        #expect(stats.fattyAcidProfile == oil.fattyAcidProfile)
    }

    @Test func oilWithoutProfile_StillHasStats() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let category = IngredientCategory(name: IngredientCategory.Name.oils)
        let oil = Ingredient(name: "Custom Oil", unit: "g")
        oil.sapValue = 0.19
        oil.category = category
        ctx.insert(category)
        ctx.insert(oil)

        let sut = IngredientChemistry(ingredient: oil)

        #expect(sut.hasFattyAcidProfile == false)
        #expect(sut.stats != nil)
    }

    @Test func oilWithAllZeroProfile_HasNoProfileButStillHasStats() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let category = IngredientCategory(name: IngredientCategory.Name.oils)
        let oil = Ingredient.mockOil(name: "Custom", naohSap: 0.19)
        oil.category = category
        ctx.insert(category)
        ctx.insert(oil)

        let sut = IngredientChemistry(ingredient: oil)

        #expect(sut.hasFattyAcidProfile == false)
        #expect(sut.stats != nil)
    }

    @Test func nonOil_ShowsNoChemistry() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let category = IngredientCategory(name: IngredientCategory.Name.fragrances)
        let fragrance = Ingredient(name: "Lavender", unit: "g")
        fragrance.category = category
        ctx.insert(category)
        ctx.insert(fragrance)

        let sut = IngredientChemistry(ingredient: fragrance)

        #expect(sut.showsChemistry == false)
        #expect(sut.stats == nil)
    }

    @Test func noCategory_ShowsNoChemistry() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let ingredient = Ingredient(name: "Mystery", unit: "g")
        ctx.insert(ingredient)

        let sut = IngredientChemistry(ingredient: ingredient)

        #expect(sut.showsChemistry == false)
        #expect(sut.stats == nil)
    }
}
