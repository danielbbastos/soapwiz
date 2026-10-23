import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Free tier limits")
@MainActor
struct FreeTierLimitsTests {

    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        let schema = ModelContainerFactory.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        context = container.mainContext
    }

    // MARK: Caps

    @Test(arguments: [0, 1, 2])
    func canCreateRecipe_UnderCap_ReturnsTrue(count: Int) {
        #expect(FreeTierLimits.canCreateRecipe(existingCount: count, isPro: false))
    }

    @Test(arguments: [3, 4, 50])
    func canCreateRecipe_AtOrOverCap_ReturnsFalse(count: Int) {
        #expect(!FreeTierLimits.canCreateRecipe(existingCount: count, isPro: false))
    }

    @Test func canCreateRecipe_Pro_IsUnlimited() {
        #expect(FreeTierLimits.canCreateRecipe(existingCount: 100, isPro: true))
    }

    // MARK: Features

    @Test(arguments: [ProFeature.collections, .reminders])
    func isAvailable_Free_ReturnsFalse(feature: ProFeature) {
        #expect(!FreeTierLimits.isAvailable(feature, isPro: false))
    }

    @Test(arguments: [ProFeature.collections, .reminders])
    func isAvailable_Pro_ReturnsTrue(feature: ProFeature) {
        #expect(FreeTierLimits.isAvailable(feature, isPro: true))
    }

    // MARK: Counting

    @Test func recipeCount_CountsAllRecipes() throws {
        #expect(try FreeTierLimits.recipeCount(in: context) == 0)

        context.insert(Recipe(name: "One"))
        context.insert(Recipe(name: "Two"))
        try context.save()

        #expect(try FreeTierLimits.recipeCount(in: context) == 2)
    }

    @Test func recipeCount_IgnoresIngredients() throws {
        for index in 0..<5 {
            context.insert(Ingredient(name: "Mine \(index)"))
        }
        try context.save()

        #expect(try FreeTierLimits.recipeCount(in: context) == 0)
    }

    // MARK: Import fit

    private func fit(
        recipes: Int = 0,
        incomingRecipes: Int = 0,
        isPro: Bool = false
    ) -> FreeTierImportFit {
        FreeTierLimits.importFit(
            existingRecipes: recipes,
            incomingRecipes: incomingRecipes,
            isPro: isPro
        )
    }

    @Test func importFit_ExactlyAtCap_Fits() {
        let result = fit(recipes: 1, incomingRecipes: FreeTierLimits.recipeCap - 1)

        #expect(result.fits)
        #expect(result.explanation == nil)
    }

    @Test func importFit_OneRecipeOverCap_ExceedsRecipes() {
        let result = fit(recipes: 1, incomingRecipes: FreeTierLimits.recipeCap)

        #expect(!result.fits)
        #expect(result.exceedsRecipes)
        #expect(result.explanation != nil)
    }

    @Test func importFit_AlreadyOverCapWithNothingIncoming_Fits() {
        #expect(fit(recipes: 9).fits)
    }

    @Test func importFit_OverCapExistingAndIncoming_DoesNotFit() {
        #expect(!fit(recipes: 9, incomingRecipes: 1).fits)
    }

    @Test func importFit_Pro_AlwaysFits() {
        #expect(fit(recipes: 100, incomingRecipes: 100, isPro: true).fits)
    }

    @Test func importFit_Explanation_NamesIncomingCapAndExisting() {
        let result = fit(recipes: 1, incomingRecipes: 5)

        let line = result.explanation
        #expect(line?.contains("5") == true)
        #expect(line?.contains("\(FreeTierLimits.recipeCap)") == true)
        #expect(line?.contains("1") == true)
    }
}
