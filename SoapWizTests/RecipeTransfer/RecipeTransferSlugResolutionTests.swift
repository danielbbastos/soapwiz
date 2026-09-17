import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// How an incoming ingredient resolves once the payload carries a library slug.
///
/// Split from `RecipeTransferPlanTests`, which covers what the plan says about
/// recipes, collections and names. These assert the narrower question the slug
/// answers: whether two devices are holding the same curated entry, and what that
/// permits the plan to stop warning about.
@MainActor
@Suite
struct RecipeTransferSlugResolutionTests {

    private let fixture: RecipeTransferFixture

    init() throws {
        fixture = try RecipeTransferFixture()
    }

    // MARK: - Resolution

    /// The point of carrying the slug: both sides hold the same curated entry, so
    /// the recipient resolves to their own copy even though the names differ.
    @Test func plan_IncomingSlugMatchesARenamedRow_ResolvesBySlug() throws {
        let recipe = fixture.recipe()
        fixture.addOil(fixture.oil("Olive Oil", slug: "olive-oil"), percentage: 100, to: recipe)
        var built = fixture.payload([recipe])
        built.ingredients[0].name = "Azeite"
        let inventory = try fixture.context.fetch(FetchDescriptor<Ingredient>())

        let plan = RecipeTransferPlan(payload: built, inventory: inventory, collections: [])

        #expect(plan.ingredientsToCreate.isEmpty)
        #expect(plan.matchedIngredients.count == 1)
    }

    /// Two devices holding the same catalog entry differ only by catalog version,
    /// which is not a disagreement about the substance. Warning here would cry wolf
    /// on every shared recipe.
    @Test func plan_SlugMatchWithDifferentChemistry_ReportsNoConflict() throws {
        let recipe = fixture.recipe()
        fixture.addOil(fixture.oil("Olive Oil", sap: 0.1345, slug: "olive-oil"), percentage: 100, to: recipe)
        var built = fixture.payload([recipe])
        built.ingredients[0].sapValue = 0.9999
        let inventory = try fixture.context.fetch(FetchDescriptor<Ingredient>())

        let plan = RecipeTransferPlan(payload: built, inventory: inventory, collections: [])

        #expect(plan.matchedIngredients.count == 1)
        #expect(plan.conflictingIngredients.isEmpty)
    }

    /// A slug match silences the warning only while the *recipient's* row is still
    /// the catalog's. Once they have customised it, their values are the ones the
    /// recipe will be calculated from and the sender never saw them — which is
    /// precisely what the warning is for.
    @Test func plan_SlugMatchAgainstCustomisedRow_StillReportsAConflict() throws {
        let recipe = fixture.recipe()
        fixture.addOil(
            fixture.oil("Olive Oil", sap: 0.1345, slug: "olive-oil", customChemistry: true),
            percentage: 100,
            to: recipe
        )
        var built = fixture.payload([recipe])
        // The sender's row was pristine, so it carried its slug; the recipient's is
        // the customised one.
        built.ingredients[0].librarySlug = "olive-oil"
        built.ingredients[0].sapValue = 0.9999
        let inventory = try fixture.context.fetch(FetchDescriptor<Ingredient>())

        let plan = RecipeTransferPlan(payload: built, inventory: inventory, collections: [])

        #expect(plan.matchedIngredients.count == 1)
        #expect(plan.conflictingIngredients.map(\.name) == ["Olive Oil"])
    }

    /// A customised row sends no slug, so it takes the name path and still discloses
    /// — the distinction the encoder draws is what keeps this honest.
    @Test func plan_NameMatchWithDifferentChemistry_StillReportsAConflict() throws {
        let recipe = fixture.recipe()
        fixture.addOil(fixture.oil("Olive Oil", sap: 0.1345, slug: "olive-oil"), percentage: 100, to: recipe)
        var built = fixture.payload([recipe])
        built.ingredients[0].librarySlug = nil
        built.ingredients[0].sapValue = 0.9999
        let inventory = try fixture.context.fetch(FetchDescriptor<Ingredient>())

        let plan = RecipeTransferPlan(payload: built, inventory: inventory, collections: [])

        #expect(plan.conflictingIngredients.map(\.name) == ["Olive Oil"])
    }

    /// A payload written before the field existed, or by a build without it.
    @Test func plan_PayloadWithoutSlugs_StillMatchesByName() throws {
        let recipe = fixture.recipe()
        fixture.addOil(fixture.oil("Olive Oil", slug: "olive-oil"), percentage: 100, to: recipe)
        var built = fixture.payload([recipe])
        built.ingredients[0].librarySlug = nil
        let inventory = try fixture.context.fetch(FetchDescriptor<Ingredient>())

        let plan = RecipeTransferPlan(payload: built, inventory: inventory, collections: [])

        #expect(plan.matchedIngredients.count == 1)
    }

    /// Sender on a newer catalog. Nothing local carries the slug and the name misses
    /// too, so it falls back to being created.
    @Test func plan_UnknownSlug_FallsBackToCreation() throws {
        let recipe = fixture.recipe()
        fixture.addOil(fixture.oil("Babassu Oil"), percentage: 100, to: recipe)
        var built = fixture.payload([recipe])
        built.ingredients[0].librarySlug = "not-in-this-catalog"
        let plan = RecipeTransferPlan(payload: built, inventory: [], collections: [])

        #expect(plan.ingredientsToCreate.count == 1)
    }

    // MARK: - adoptableSlug

    @Test func adoptableSlug_KnownSlug_IsCarried() throws {
        let recipe = fixture.recipe()
        fixture.addOil(fixture.oil("Olive Oil", slug: "olive-oil"), percentage: 100, to: recipe)
        let plan = RecipeTransferPlan(payload: fixture.payload([recipe]), inventory: [], collections: [])

        #expect(try #require(plan.ingredients.first).adoptableSlug == "olive-oil")
    }

    /// The decision this whole path rests on: an unknown slug is dropped so the
    /// installer can adopt the row by name later and flag its chemistry as custom,
    /// rather than counting the entry as present and leaving the sender's values
    /// wearing the built-in badge for good.
    @Test func adoptableSlug_UnknownSlug_IsDropped() throws {
        let recipe = fixture.recipe()
        fixture.addOil(fixture.oil("Babassu Oil"), percentage: 100, to: recipe)
        var built = fixture.payload([recipe])
        built.ingredients[0].librarySlug = "not-in-this-catalog"
        let plan = RecipeTransferPlan(payload: built, inventory: [], collections: [])

        #expect(try #require(plan.ingredients.first).adoptableSlug == nil)
    }

    @Test func adoptableSlug_NoSlug_IsNil() throws {
        let recipe = fixture.recipe()
        fixture.addOil(fixture.oil("House Blend"), percentage: 100, to: recipe)
        let plan = RecipeTransferPlan(payload: fixture.payload([recipe]), inventory: [], collections: [])

        #expect(try #require(plan.ingredients.first).adoptableSlug == nil)
    }
}
