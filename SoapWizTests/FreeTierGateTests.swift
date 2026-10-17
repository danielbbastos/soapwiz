import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Free tier gate")
@MainActor
struct FreeTierGateTests {

    private let container: ModelContainer
    private let context: ModelContext
    private let entry: IngredientLibraryEntry

    init() throws {
        let schema = ModelContainerFactory.schema
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        context = container.mainContext
        entry = try #require(IngredientLibrary.bundled.entries.first)
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

    // MARK: Custom ingredients

    @Test(arguments: [0, 1, 2])
    func canCreateCustomIngredient_UnderCap_ReturnsTrue(count: Int) throws {
        try addCustomIngredients(count)

        #expect(free.canCreateCustomIngredient(in: context))
    }

    @Test(arguments: [3, 4, 10])
    func canCreateCustomIngredient_AtOrOverCap_ReturnsFalse(count: Int) throws {
        try addCustomIngredients(count)

        #expect(!free.canCreateCustomIngredient(in: context))
    }

    @Test func canCreateCustomIngredient_LibraryRowsDoNotCount() throws {
        try addCustomIngredients(2)
        for _ in 0..<5 {
            let row = Ingredient(name: entry.name)
            row.librarySlug = entry.slug
            context.insert(row)
        }
        try context.save()

        #expect(free.canCreateCustomIngredient(in: context))
    }

    @Test func canCreateCustomIngredient_Pro_IgnoresTheCap() throws {
        try addCustomIngredients(10)

        #expect(FreeTierGate(isPro: true).canCreateCustomIngredient(in: context))
    }

    @Test func canCreateCustomIngredient_TourSandbox_IgnoresTheCap() throws {
        try addCustomIngredients(10)

        #expect(FreeTierGate(isPro: false, isTourSandbox: true).canCreateCustomIngredient(in: context))
    }

    // MARK: Rename

    @Test func allowsRename_ToCustomWithNoSlotLeft_ReturnsFalse() throws {
        try addCustomIngredients(FreeTierLimits.customIngredientCap)

        #expect(!free.allowsRename(
            librarySlug: entry.slug,
            oldName: entry.name,
            newName: "My own name",
            in: context
        ))
    }

    @Test func allowsRename_ToCustomWithASlotLeft_ReturnsTrue() throws {
        try addCustomIngredients(FreeTierLimits.customIngredientCap - 1)

        #expect(free.allowsRename(
            librarySlug: entry.slug,
            oldName: entry.name,
            newName: "My own name",
            in: context
        ))
    }

    @Test func allowsRename_Pro_ReturnsTrueAtCap() throws {
        try addCustomIngredients(FreeTierLimits.customIngredientCap)

        #expect(FreeTierGate(isPro: true).allowsRename(
            librarySlug: entry.slug,
            oldName: entry.name,
            newName: "My own name",
            in: context
        ))
    }

    @Test func allowsRename_RenamedBackAtCap_ReturnsTrue() throws {
        try addCustomIngredients(FreeTierLimits.customIngredientCap)

        #expect(free.allowsRename(
            librarySlug: entry.slug,
            oldName: "My own name",
            newName: entry.name,
            in: context
        ))
    }

    @Test func allowsRename_CustomRowEditedAtCap_ReturnsTrue() throws {
        try addCustomIngredients(FreeTierLimits.customIngredientCap)

        #expect(free.allowsRename(librarySlug: "", oldName: "Mine 0", newName: "Mine zero", in: context))
    }

    @Test func allowsRename_UnknownSlugAtCap_ReturnsTrue() throws {
        try addCustomIngredients(FreeTierLimits.customIngredientCap)

        #expect(free.allowsRename(librarySlug: "no-such-slug", oldName: "Old", newName: "New", in: context))
    }
}
