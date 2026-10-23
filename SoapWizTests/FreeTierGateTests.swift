import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Free tier gate")
@MainActor
struct FreeTierGateTests {

    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        let schema = ModelContainerFactory.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        context = container.mainContext
    }

    private let free = FreeTierGate(isPro: false)

    private func addRecipes(_ count: Int) throws {
        for index in 0..<count {
            context.insert(Recipe(name: "Recipe \(index)"))
        }
        try context.save()
    }

    private func addCustomIngredients(_ count: Int) throws {
        for index in 0..<count {
            context.insert(Ingredient(name: "Mine \(index)"))
        }
        try context.save()
    }

    // MARK: Pro features

    @Test(arguments: [ProFeature.collections, .reminders])
    func allows_FreeUser_ReturnsFalse(feature: ProFeature) {
        #expect(!free.allows(feature))
    }

    @Test(arguments: [ProFeature.collections, .reminders])
    func allows_ProUser_ReturnsTrue(feature: ProFeature) {
        #expect(FreeTierGate(isPro: true).allows(feature))
    }

    @Test(arguments: [ProFeature.collections, .reminders])
    func allows_TourSandbox_ReturnsTrue(feature: ProFeature) {
        #expect(FreeTierGate(isPro: false, isTourSandbox: true).allows(feature))
    }

    @Test func mayToggleCollection_FreeUserFiling_ReturnsFalse() {
        #expect(!free.mayToggleCollection(isFiled: false))
    }

    @Test func mayToggleCollection_FreeUserUnfiling_ReturnsTrue() {
        #expect(free.mayToggleCollection(isFiled: true))
    }

    @Test(arguments: [true, false])
    func mayToggleCollection_ProUser_ReturnsTrue(isFiled: Bool) {
        #expect(FreeTierGate(isPro: true).mayToggleCollection(isFiled: isFiled))
    }

    // MARK: Recipes

    @Test(arguments: [0, 1, 2])
    func canCreateRecipe_UnderCap_ReturnsTrue(count: Int) throws {
        try addRecipes(count)

        #expect(free.canCreateRecipe(in: context))
    }

    @Test(arguments: [3, 4, 10])
    func canCreateRecipe_AtOrOverCap_ReturnsFalse(count: Int) throws {
        try addRecipes(count)

        #expect(!free.canCreateRecipe(in: context))
    }

    @Test func canCreateRecipe_Pro_IgnoresTheCap() throws {
        try addRecipes(10)

        #expect(FreeTierGate(isPro: true).canCreateRecipe(in: context))
    }

    @Test func canCreateRecipe_TourSandbox_IgnoresTheCap() throws {
        try addRecipes(10)

        #expect(FreeTierGate(isPro: false, isTourSandbox: true).canCreateRecipe(in: context))
    }

    @Test func canCreateRecipe_ManyCustomIngredients_DoesNotAffectTheCap() throws {
        try addCustomIngredients(10)
        try addRecipes(FreeTierLimits.recipeCap - 1)

        #expect(free.canCreateRecipe(in: context))
    }
}
