import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The launch pass that fills the inventory from the bundled library, adopting
/// what the user already has instead of duplicating it.
@Suite("Ingredient library installer", .serialized)
@MainActor
struct IngredientLibraryInstallerTests {

    private let olive = IngredientLibraryEntry.mock(slug: "olive-oil", name: "Olive Oil", aliases: ["Extra Virgin Olive Oil"])
    private let lye = IngredientLibraryEntry.mock(
        slug: "sodium-hydroxide",
        name: "Sodium Hydroxide",
        category: IngredientCategory.Name.lyes,
        sapValue: nil,
        kohSapValue: nil,
        density: nil,
        fattyAcidProfile: nil
    )

    private var library: IngredientLibrary { IngredientLibrary(entries: [olive, lye]) }

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    private func ingredients(_ ctx: ModelContext) throws -> [Ingredient] {
        try ctx.fetch(FetchDescriptor<Ingredient>())
    }

    private func ingredient(slug: String, in ctx: ModelContext) throws -> Ingredient {
        try #require(try ingredients(ctx).first { $0.librarySlug == slug })
    }

    private func categoryNames(_ ctx: ModelContext) throws -> [String] {
        try ctx.fetch(FetchDescriptor<IngredientCategory>()).map(\.name).sorted()
    }

    // MARK: - Fresh store

    @Test func install_EmptyStore_InsertsEveryEntryWithItsChemistry() throws {
        let (container, ctx) = try makeContext()
        _ = container

        try IngredientLibraryInstaller.installMissing(from: library, in: ctx)

        let installed = try ingredient(slug: "olive-oil", in: ctx)
        #expect(try ingredients(ctx).count == 2)
        #expect(installed.name == "Olive Oil")
        #expect(installed.category?.name == IngredientCategory.Name.oils)
        #expect(installed.unit == IngredientUnit.grams.rawValue)
        #expect(olive.hasSameChemistry(as: installed))
        #expect(installed.isLibrary)
        #expect(installed.purchases.isEmpty)
    }

    @Test func install_EmptyStore_CreatesEveryDefaultCategory() throws {
        let (container, ctx) = try makeContext()
        _ = container

        try IngredientLibraryInstaller.installMissing(from: library, in: ctx)

        let names = try ctx.fetch(FetchDescriptor<IngredientCategory>()).map(\.name)
        #expect(names.count == IngredientCategory.Name.all.count)
        #expect(Set(names) == Set(IngredientCategory.Name.all))
    }

    @Test func install_EmptyLibrary_StillCreatesTheDefaultCategories() throws {
        let (container, ctx) = try makeContext()
        _ = container

        try IngredientLibraryInstaller.installMissing(from: IngredientLibrary(entries: []), in: ctx)

        #expect(try ctx.fetchCount(FetchDescriptor<IngredientCategory>()) == IngredientCategory.Name.all.count)
        #expect(try ingredients(ctx).isEmpty)
    }

    @Test func install_SecondRun_ChangesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try IngredientLibraryInstaller.installMissing(from: library, in: ctx)

        let changes = try IngredientLibraryInstaller.installMissing(from: library, in: ctx)

        #expect(changes == 0)
        #expect(try ingredients(ctx).count == 2)
        #expect(try ctx.fetchCount(FetchDescriptor<IngredientCategory>()) == IngredientCategory.Name.all.count)
    }

    @Test func install_EntryAddedToTheLibraryLater_IsInstalled() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try IngredientLibraryInstaller.installMissing(from: IngredientLibrary(entries: [olive]), in: ctx)

        let changes = try IngredientLibraryInstaller.installMissing(from: library, in: ctx)

        #expect(changes == 1)
        #expect(try ingredient(slug: "sodium-hydroxide", in: ctx).category?.name == IngredientCategory.Name.lyes)
    }

    @Test func install_DuplicateSlugInTheLibrary_InstallsItOnce() throws {
        let (container, ctx) = try makeContext()
        _ = container

        try IngredientLibraryInstaller.installMissing(from: IngredientLibrary(entries: [olive, olive]), in: ctx)

        #expect(try ingredients(ctx).count == 1)
    }

    // MARK: - Existing store

    @Test func install_ExistingCategoryWithDifferentCase_IsReused() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let existing = IngredientCategory(name: "oils")
        ctx.insert(existing)
        try ctx.save()

        try IngredientLibraryInstaller.installMissing(from: library, in: ctx)

        #expect(try ingredient(slug: "olive-oil", in: ctx).category === existing)
        #expect(try Set(categoryNames(ctx)) == ["oils", IngredientCategory.Name.lyes])
    }

    // MARK: - Categories the user changed

    @Test func install_DeletedDefaultCategory_IsNotRecreated() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try IngredientLibraryInstaller.installMissing(from: library, in: ctx)
        let categories = try ctx.fetch(FetchDescriptor<IngredientCategory>())
        let others = try #require(categories.first { $0.name == IngredientCategory.Name.others })
        ctx.delete(others)
        try ctx.save()

        let changes = try IngredientLibraryInstaller.installMissing(from: library, in: ctx)

        #expect(changes == 0)
        #expect(try !categoryNames(ctx).contains(IngredientCategory.Name.others))
    }

    @Test func install_RenamedCategory_IsNotRecreated() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try IngredientLibraryInstaller.installMissing(from: library, in: ctx)
        let oils = try #require(try ctx.fetch(FetchDescriptor<IngredientCategory>()).first { $0.name == IngredientCategory.Name.oils })
        oils.name = "Óleos"
        try ctx.save()

        let changes = try IngredientLibraryInstaller.installMissing(from: library, in: ctx)

        #expect(changes == 0)
        #expect(try !categoryNames(ctx).contains(IngredientCategory.Name.oils))
        #expect(try ingredient(slug: "olive-oil", in: ctx).category === oils)
    }

    @Test func install_NewEntryNeedingADeletedCategory_RecreatesOnlyThatCategory() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try IngredientLibraryInstaller.installMissing(from: IngredientLibrary(entries: [olive]), in: ctx)
        for category in try ctx.fetch(FetchDescriptor<IngredientCategory>())
        where [IngredientCategory.Name.lyes, IngredientCategory.Name.others].contains(category.name) {
            ctx.delete(category)
        }
        try ctx.save()

        try IngredientLibraryInstaller.installMissing(from: library, in: ctx)

        let names = try categoryNames(ctx)
        #expect(names.contains(IngredientCategory.Name.lyes))
        #expect(!names.contains(IngredientCategory.Name.others))
        #expect(try ingredient(slug: "sodium-hydroxide", in: ctx).category?.name == IngredientCategory.Name.lyes)
    }

    @Test func install_HiddenOrCustomisedLibraryIngredient_IsNotInstalledAgain() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let customised = Ingredient(name: "My Olive", unit: "g")
        customised.librarySlug = "olive-oil"
        customised.hasCustomChemistry = true
        customised.isHidden = true
        ctx.insert(customised)
        try ctx.save()

        try IngredientLibraryInstaller.installMissing(from: library, in: ctx)

        #expect(try ingredients(ctx).count == 2)
        #expect(try ingredients(ctx).filter { $0.librarySlug == "olive-oil" }.count == 1)
    }

    @Test func install_UserIngredientWithAnotherName_IsLeftAlone() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let blend = Ingredient(name: "House Blend", unit: "g")
        ctx.insert(blend)
        try ctx.save()

        try IngredientLibraryInstaller.installMissing(from: library, in: ctx)

        #expect(try ingredients(ctx).count == 3)
        #expect(blend.librarySlug.isEmpty)
        #expect(!blend.hasCustomChemistry)
    }

    // MARK: - Adoption

    @Test func install_UserIngredientWithSameNameAndChemistry_IsAdoptedAsLibrary() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let existing = Ingredient.mock(matching: olive, name: "olive oil")
        ctx.insert(existing)
        try ctx.save()

        try IngredientLibraryInstaller.installMissing(from: library, in: ctx)

        #expect(try ingredients(ctx).count == 2)
        #expect(existing.librarySlug == "olive-oil")
        #expect(existing.isLibrary)
    }

    @Test func install_UserIngredientWithDifferentChemistry_IsAdoptedAsCustom() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let existing = Ingredient.mock(matching: olive)
        existing.sapValue = 0.2
        ctx.insert(existing)
        try ctx.save()

        try IngredientLibraryInstaller.installMissing(from: library, in: ctx)

        #expect(try ingredients(ctx).count == 2)
        #expect(existing.librarySlug == "olive-oil")
        #expect(existing.hasCustomChemistry)
        #expect(existing.sapValue == 0.2)
    }

    @Test func install_UserIngredientMatchingAnAlias_IsAdoptedAndKeepsItsName() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let existing = Ingredient.mock(matching: olive, name: "Extra Virgin Olive Oil")
        ctx.insert(existing)
        try ctx.save()

        try IngredientLibraryInstaller.installMissing(from: library, in: ctx)

        #expect(try ingredients(ctx).count == 2)
        #expect(existing.librarySlug == "olive-oil")
        #expect(existing.name == "Extra Virgin Olive Oil")
    }

    @Test func install_AdoptedIngredient_KeepsItsPurchasesUnitAndCategory() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let category = IngredientCategory(name: "Pantry Oils")
        ctx.insert(category)
        let existing = Ingredient(name: "Olive Oil", category: category, unit: "ml")
        ctx.insert(existing)
        let purchase = IngredientPurchase(
            dateOfPurchase: .now,
            quantity: 1000,
            totalPrice: 9,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        existing.purchases.append(purchase)
        ctx.insert(purchase)
        try ctx.save()

        try IngredientLibraryInstaller.installMissing(from: library, in: ctx)

        #expect(existing.librarySlug == "olive-oil")
        #expect(existing.purchases.count == 1)
        #expect(existing.unit == "ml")
        #expect(existing.category === category)
    }

    @Test func install_AdoptedIngredientWithoutCategory_TakesTheLibraryCategory() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let existing = Ingredient.mock(matching: olive)
        ctx.insert(existing)
        try ctx.save()

        try IngredientLibraryInstaller.installMissing(from: library, in: ctx)

        #expect(existing.category?.name == IngredientCategory.Name.oils)
    }

    @Test func install_TwoUserIngredientsWithTheSameName_AdoptsOnlyOne() throws {
        let (container, ctx) = try makeContext()
        _ = container
        ctx.insert(Ingredient.mock(matching: olive))
        ctx.insert(Ingredient.mock(matching: olive))
        try ctx.save()

        try IngredientLibraryInstaller.installMissing(from: library, in: ctx)

        let olives = try ingredients(ctx).filter { $0.name == "Olive Oil" }
        #expect(olives.count == 2)
        #expect(olives.filter { $0.librarySlug == "olive-oil" }.count == 1)
    }
}
