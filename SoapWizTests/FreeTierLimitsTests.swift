import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Free tier limits")
@MainActor
struct FreeTierLimitsTests {

    private let container: ModelContainer
    private let context: ModelContext
    private let entry: IngredientLibraryEntry

    init() throws {
        let schema = ModelContainerFactory.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        context = container.mainContext
        entry = try #require(IngredientLibrary.bundled.entries.first)
    }

    private func libraryRow(name: String? = nil) -> Ingredient {
        let ingredient = Ingredient(name: name ?? entry.name)
        ingredient.librarySlug = entry.slug
        context.insert(ingredient)
        return ingredient
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

    @Test(arguments: [0, 1, 2])
    func canCreateCustomIngredient_UnderCap_ReturnsTrue(count: Int) {
        #expect(FreeTierLimits.canCreateCustomIngredient(existingCount: count, isPro: false))
    }

    @Test(arguments: [3, 4, 50])
    func canCreateCustomIngredient_AtOrOverCap_ReturnsFalse(count: Int) {
        #expect(!FreeTierLimits.canCreateCustomIngredient(existingCount: count, isPro: false))
    }

    @Test func canCreateCustomIngredient_Pro_IsUnlimited() {
        #expect(FreeTierLimits.canCreateCustomIngredient(existingCount: 100, isPro: true))
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

    // MARK: Custom ingredient rule

    @Test func isCustomIngredient_EmptySlug_ReturnsTrue() {
        #expect(FreeTierLimits.isCustomIngredient(librarySlug: "", name: "Anything"))
    }

    @Test func isCustomIngredient_UnknownSlug_ReturnsFalse() {
        #expect(!FreeTierLimits.isCustomIngredient(librarySlug: "no-such-slug", name: "Anything"))
    }

    @Test func isCustomIngredient_BundledName_ReturnsFalse() {
        #expect(!FreeTierLimits.isCustomIngredient(librarySlug: entry.slug, name: entry.name))
    }

    @Test func isCustomIngredient_CaseAndWhitespaceVariant_ReturnsFalse() {
        let variant = "  \(entry.name.uppercased()) \n"
        #expect(!FreeTierLimits.isCustomIngredient(librarySlug: entry.slug, name: variant))
    }

    @Test func isCustomIngredient_RenamedLibraryRow_ReturnsTrue() {
        #expect(FreeTierLimits.isCustomIngredient(librarySlug: entry.slug, name: entry.name + " from the farm"))
    }

    // MARK: Counting

    @Test func customIngredientCount_EmptyStore_ReturnsZero() throws {
        #expect(try FreeTierLimits.customIngredientCount(in: context) == 0)
    }

    @Test func customIngredientCount_PristineLibraryRow_IsNotCounted() throws {
        _ = libraryRow()
        try context.save()

        #expect(try FreeTierLimits.customIngredientCount(in: context) == 0)
    }

    @Test func customIngredientCount_ChemistryEdited_IsNotCounted() throws {
        let ingredient = libraryRow()
        ingredient.sapValue = 0.123
        ingredient.kohSapValue = 0.173
        ingredient.hasCustomChemistry = true
        try context.save()

        #expect(try FreeTierLimits.customIngredientCount(in: context) == 0)
    }

    @Test func customIngredientCount_CategoryOnlyChange_IsNotCounted() throws {
        let ingredient = libraryRow()
        let category = IngredientCategory(name: "My own category")
        context.insert(category)
        ingredient.category = category
        try context.save()

        #expect(try FreeTierLimits.customIngredientCount(in: context) == 0)
    }

    @Test func customIngredientCount_Renamed_IsCounted() throws {
        _ = libraryRow(name: entry.name + " from the farm")
        try context.save()

        #expect(try FreeTierLimits.customIngredientCount(in: context) == 1)
    }

    @Test func customIngredientCount_RenamedBack_IsNotCounted() throws {
        let ingredient = libraryRow(name: entry.name + " from the farm")
        ingredient.name = entry.name
        try context.save()

        #expect(try FreeTierLimits.customIngredientCount(in: context) == 0)
    }

    @Test func customIngredientCount_CaseAndWhitespaceVariant_IsNotCounted() throws {
        _ = libraryRow(name: " \(entry.name.lowercased()) ")
        try context.save()

        #expect(try FreeTierLimits.customIngredientCount(in: context) == 0)
    }

    @Test func customIngredientCount_EmptySlug_IsCounted() throws {
        context.insert(Ingredient(name: "Mine"))
        try context.save()

        #expect(try FreeTierLimits.customIngredientCount(in: context) == 1)
    }

    @Test func customIngredientCount_UnknownSlug_IsNotCounted() throws {
        let ingredient = Ingredient(name: "Retired")
        ingredient.librarySlug = "no-such-slug"
        context.insert(ingredient)
        try context.save()

        #expect(try FreeTierLimits.customIngredientCount(in: context) == 0)
    }

    @Test func customIngredientCount_HiddenCustom_IsStillCounted() throws {
        let ingredient = Ingredient(name: "Mine")
        ingredient.isHidden = true
        context.insert(ingredient)
        try context.save()

        #expect(try FreeTierLimits.customIngredientCount(in: context) == 1)
    }

    @Test func customIngredientCount_Mixed_CountsOnlyCustom() throws {
        _ = libraryRow()
        context.insert(Ingredient(name: "Mine"))
        _ = libraryRow(name: "Renamed")
        try context.save()

        #expect(try FreeTierLimits.customIngredientCount(in: context) == 2)
    }

    @Test func recipeCount_CountsAllRecipes() throws {
        #expect(try FreeTierLimits.recipeCount(in: context) == 0)

        context.insert(Recipe(name: "One"))
        context.insert(Recipe(name: "Two"))
        try context.save()

        #expect(try FreeTierLimits.recipeCount(in: context) == 2)
    }

    // MARK: Rename

    @Test func renameNeedsSlot_LibraryNameToOwnName_ReturnsTrue() {
        #expect(FreeTierLimits.renameNeedsSlot(
            librarySlug: entry.slug,
            oldName: entry.name,
            newName: entry.name + " from the farm"
        ))
    }

    @Test func renameNeedsSlot_UnchangedName_ReturnsFalse() {
        #expect(!FreeTierLimits.renameNeedsSlot(librarySlug: entry.slug, oldName: entry.name, newName: entry.name))
    }

    @Test func renameNeedsSlot_CaseAndWhitespaceOnly_ReturnsFalse() {
        #expect(!FreeTierLimits.renameNeedsSlot(
            librarySlug: entry.slug,
            oldName: entry.name,
            newName: " \(entry.name.uppercased()) "
        ))
    }

    @Test func renameNeedsSlot_RenamedBackToCatalogName_ReturnsFalse() {
        #expect(!FreeTierLimits.renameNeedsSlot(
            librarySlug: entry.slug,
            oldName: entry.name + " from the farm",
            newName: entry.name
        ))
    }

    @Test func renameNeedsSlot_AlreadyRenamedRow_ReturnsFalse() {
        #expect(!FreeTierLimits.renameNeedsSlot(
            librarySlug: entry.slug,
            oldName: entry.name + " from the farm",
            newName: entry.name + " from the market"
        ))
    }

    @Test func renameNeedsSlot_EmptySlug_ReturnsFalse() {
        #expect(!FreeTierLimits.renameNeedsSlot(librarySlug: "", oldName: "Mine", newName: "Still mine"))
    }

    @Test func renameNeedsSlot_UnknownSlug_ReturnsFalse() {
        #expect(!FreeTierLimits.renameNeedsSlot(librarySlug: "no-such-slug", oldName: "Old", newName: "New"))
    }

    // MARK: Import fit

    private func fit(
        recipes: Int = 0,
        customs: Int = 0,
        incomingRecipes: Int = 0,
        incomingCustoms: Int = 0,
        isPro: Bool = false
    ) -> FreeTierImportFit {
        FreeTierLimits.importFit(
            existingRecipes: recipes,
            existingCustomIngredients: customs,
            incomingRecipes: incomingRecipes,
            incomingCustomIngredients: incomingCustoms,
            isPro: isPro
        )
    }

    @Test func importFit_ExactlyAtBothCaps_Fits() {
        let result = fit(
            recipes: 1,
            customs: 2,
            incomingRecipes: FreeTierLimits.recipeCap - 1,
            incomingCustoms: FreeTierLimits.customIngredientCap - 2
        )

        #expect(result.fits)
        #expect(result.upgradeReason == nil)
        #expect(result.explanations.isEmpty)
    }

    @Test func importFit_OneRecipeOverCap_ExceedsRecipesOnly() {
        let result = fit(recipes: 1, incomingRecipes: FreeTierLimits.recipeCap)

        #expect(!result.fits)
        #expect(result.exceedsRecipes)
        #expect(!result.exceedsCustomIngredients)
        #expect(result.upgradeReason == .recipeImportLimit)
        #expect(result.explanations.count == 1)
    }

    @Test func importFit_OneCustomOverCap_ExceedsIngredientsOnly() {
        let result = fit(customs: FreeTierLimits.customIngredientCap, incomingCustoms: 1)

        #expect(!result.fits)
        #expect(!result.exceedsRecipes)
        #expect(result.exceedsCustomIngredients)
        #expect(result.upgradeReason == .customIngredientImportLimit)
    }

    @Test func importFit_BothOver_ReportsBothAndNamesRecipesFirst() {
        let result = fit(incomingRecipes: 10, incomingCustoms: 10)

        #expect(result.exceedsRecipes)
        #expect(result.exceedsCustomIngredients)
        #expect(result.upgradeReason == .recipeImportLimit)
        #expect(result.explanations.count == 2)
    }

    @Test func importFit_AlreadyOverCapWithNothingIncoming_Fits() {
        #expect(fit(recipes: 9, customs: 9).fits)
    }

    @Test func importFit_OverCapExistingAndIncoming_DoesNotFit() {
        #expect(!fit(recipes: 9, incomingRecipes: 1).fits)
    }

    @Test func importFit_Pro_AlwaysFits() {
        #expect(fit(recipes: 100, customs: 100, incomingRecipes: 100, incomingCustoms: 100, isPro: true).fits)
    }

    @Test func importFit_Explanation_NamesIncomingCapAndExisting() {
        let result = fit(recipes: 1, incomingRecipes: 5)

        let line = result.explanations.first
        #expect(line?.contains("5") == true)
        #expect(line?.contains("\(FreeTierLimits.recipeCap)") == true)
        #expect(line?.contains("1") == true)
    }
}
