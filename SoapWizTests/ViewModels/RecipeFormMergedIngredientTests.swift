import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// A recipe screen that loaded its drafts before the duplicate merge ran still
/// holds the copy the merge deleted, and the next redraw reads it. SW-209 was
/// that read trapping on the recipe detail screen, in `RecipeStats`, after a
/// CloudKit import collapsed a library oil while the recipe was open.
@Suite("Recipe form — ingredients merged while open", .serialized)
@MainActor
struct RecipeFormMergedIngredientTests {

    /// The full schema: `DuplicateMerger` fetches providers, storage locations
    /// and settings too.
    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    private func uuid(_ index: Int) throws -> UUID {
        try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)"))
    }

    /// A library row. The lowest `uuid` is the one the merge keeps.
    private func installed(_ slug: String, _ index: Int, in ctx: ModelContext) throws -> Ingredient {
        let row = Ingredient(name: slug, unit: IngredientUnit.grams.rawValue)
        row.librarySlug = slug
        row.sapValue = 0.135
        row.fattyAcidProfile = FattyAcidProfile(palmitic: 13, stearic: 3, oleic: 71, linoleic: 10)
        row.uuid = try uuid(index)
        ctx.insert(row)
        return row
    }

    private func makeRecipe(oil: Ingredient, amount: Double = 100, in ctx: ModelContext) -> Recipe {
        let recipe = Recipe(name: "Castile")
        ctx.insert(recipe)
        let line = RecipeIngredient(ingredient: oil, percentage: amount, role: .oil)
        line.recipe = recipe
        ctx.insert(line)
        return recipe
    }

    private func loadedModel(from recipe: Recipe) -> RecipeFormViewModel {
        let model = RecipeFormViewModel()
        model.load(from: recipe)
        model.captureSnapshot()
        return model
    }

    // MARK: - Detail screen

    /// The detail screen's fix is to reload, which is only safe because the
    /// merge has already moved the recipe's line items onto the survivor.
    @Test func load_AfterMergeDeletedTheLoadedOil_DraftsPointAtTheSurvivor() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installed("olive-oil", 1, in: ctx)
        let captured = try installed("olive-oil", 2, in: ctx)
        let recipe = makeRecipe(oil: captured, in: ctx)
        try ctx.save()
        let model = loadedModel(from: recipe)

        try DuplicateMerger.mergeAll(in: ctx)
        model.load(from: recipe)

        let draft = try #require(model.oilDrafts.first)
        #expect(model.oilDrafts.count == 1)
        #expect(draft.ingredient === keep)
        #expect(RecipeStats(oilDrafts: model.oilDrafts).hasFattyAcidData)
    }

    // MARK: - Open form

    @Test func resolveMergedIngredients_OilMergedAway_DraftMovesOntoTheSurvivorKeepingItsRow() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installed("olive-oil", 1, in: ctx)
        let captured = try installed("olive-oil", 2, in: ctx)
        let recipe = makeRecipe(oil: captured, amount: 70, in: ctx)
        try ctx.save()
        let model = loadedModel(from: recipe)
        let draftID = try #require(model.oilDrafts.first?.id)

        try DuplicateMerger.mergeAll(in: ctx)
        #expect(captured.modelContext == nil)
        model.resolveMergedIngredients(in: ctx)

        let draft = try #require(model.oilDrafts.first)
        #expect(model.oilDrafts.count == 1)
        #expect(draft.ingredient === keep)
        #expect(draft.id == draftID)
        #expect(draft.amount == 70)
        #expect(RecipeStats(oilDrafts: model.oilDrafts).hasFattyAcidData)
    }

    /// A merge isn't an edit, so it must not leave the form asking to discard.
    @Test func resolveMergedIngredients_UneditedForm_StaysClean() throws {
        let (container, ctx) = try makeContext()
        _ = container
        _ = try installed("olive-oil", 1, in: ctx)
        let captured = try installed("olive-oil", 2, in: ctx)
        let recipe = makeRecipe(oil: captured, in: ctx)
        recipe.lyeIngredient = captured
        try ctx.save()
        let model = loadedModel(from: recipe)

        try DuplicateMerger.mergeAll(in: ctx)
        model.resolveMergedIngredients(in: ctx)

        #expect(!model.isDirty)
    }

    /// The baseline follows the merge without swallowing a real edit.
    @Test func resolveMergedIngredients_EditedForm_StaysDirty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        _ = try installed("olive-oil", 1, in: ctx)
        let captured = try installed("olive-oil", 2, in: ctx)
        let recipe = makeRecipe(oil: captured, in: ctx)
        try ctx.save()
        let model = loadedModel(from: recipe)
        model.name = "Bastille"

        try DuplicateMerger.mergeAll(in: ctx)
        model.resolveMergedIngredients(in: ctx)

        #expect(model.isDirty)
    }

    @Test func resolveMergedIngredients_AdditiveAndFragranceMergedAway_BothMoveOntoTheSurvivors() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = try installed("olive-oil", 1, in: ctx)
        let keepSugar = try installed("sugar", 2, in: ctx)
        let capturedSugar = try installed("sugar", 3, in: ctx)
        let keepLavender = try installed("lavender", 4, in: ctx)
        let capturedLavender = try installed("lavender", 5, in: ctx)
        let recipe = makeRecipe(oil: oil, in: ctx)
        for (ingredient, role) in [(capturedSugar, RecipeIngredientRole.additive), (capturedLavender, .fragrance)] {
            let line = RecipeIngredient(ingredient: ingredient, percentage: 0, role: role)
            line.additiveAmount = 10
            line.additiveUnit = "g"
            line.recipe = recipe
            ctx.insert(line)
        }
        try ctx.save()
        let model = loadedModel(from: recipe)

        try DuplicateMerger.mergeAll(in: ctx)
        model.resolveMergedIngredients(in: ctx)

        #expect(model.additiveDrafts.map(\.ingredient) == [keepSugar])
        #expect(model.fragranceDrafts.map(\.ingredient) == [keepLavender])
        #expect(model.additiveDrafts.first?.amount == 10)
    }

    @Test func resolveMergedIngredients_LyeAndNeutralizerMergedAway_MoveOntoTheSurvivors() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = try installed("olive-oil", 1, in: ctx)
        let keepLye = try installed("sodium-hydroxide", 2, in: ctx)
        let capturedLye = try installed("sodium-hydroxide", 3, in: ctx)
        let keepBoric = try installed("boric-acid", 4, in: ctx)
        let capturedBoric = try installed("boric-acid", 5, in: ctx)
        let recipe = makeRecipe(oil: oil, in: ctx)
        recipe.lyeIngredient = capturedLye
        recipe.neutralizerIngredient = capturedBoric
        try ctx.save()
        let model = loadedModel(from: recipe)

        try DuplicateMerger.mergeAll(in: ctx)
        model.resolveMergedIngredients(in: ctx)

        #expect(model.lyeIngredient === keepLye)
        #expect(model.neutralizerIngredient === keepBoric)
    }

    /// No survivor to move onto: the row goes rather than staying on a deleted
    /// ingredient the next redraw would read.
    @Test func resolveMergedIngredients_UserOilDeletedOutright_DraftIsDropped() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let kept = try installed("olive-oil", 1, in: ctx)
        let userOil = Ingredient(name: "Kokum Butter", unit: IngredientUnit.grams.rawValue)
        ctx.insert(userOil)
        try ctx.save()
        let model = RecipeFormViewModel()
        model.addOil(kept)
        model.addOil(userOil)

        ctx.delete(userOil)
        try ctx.save()
        model.resolveMergedIngredients(in: ctx)

        #expect(model.oilDrafts.map(\.ingredient) == [kept])
    }

    /// The ordinary path, so the tests above cannot pass by rebuilding rows that
    /// had nothing wrong with them.
    @Test func resolveMergedIngredients_NothingMerged_LeavesEveryRowAsItWas() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = try installed("olive-oil", 1, in: ctx)
        let lye = try installed("sodium-hydroxide", 2, in: ctx)
        let recipe = makeRecipe(oil: oil, amount: 55, in: ctx)
        recipe.lyeIngredient = lye
        try ctx.save()
        let model = loadedModel(from: recipe)
        let before = model.oilDrafts

        model.resolveMergedIngredients(in: ctx)

        #expect(model.oilDrafts == before)
        #expect(model.lyeIngredient === lye)
        #expect(!model.isDirty)
    }
}
