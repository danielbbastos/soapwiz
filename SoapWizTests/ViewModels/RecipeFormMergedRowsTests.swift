import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// A recipe screen that loaded its rows before the duplicate merge ran still
/// holds the copy the merge deleted, and the next redraw reads it. SW-209 was
/// that read trapping on the recipe detail screen, in `RecipeStats`, after a
/// CloudKit import collapsed a library oil while the recipe was open.
///
/// A regression here traps rather than failing an expectation, which is still
/// a failed run.
@Suite("Recipe screens — rows merged while open", .serialized)
@MainActor
struct RecipeFormMergedRowsTests {

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
        try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000\(String(format: "%02d", index))"))
    }

    /// A library row. Of two sharing a slug, the lowest `uuid` is the one the
    /// merge keeps.
    private func installed(
        _ slug: String,
        _ index: Int,
        category: IngredientCategory? = nil,
        in ctx: ModelContext
    ) throws -> Ingredient {
        let row = Ingredient(name: slug, unit: IngredientUnit.grams.rawValue)
        row.librarySlug = slug
        row.category = category
        row.sapValue = 0.135
        row.fattyAcidProfile = FattyAcidProfile(palmitic: 13, stearic: 3, oleic: 71, linoleic: 10)
        row.uuid = try uuid(index)
        ctx.insert(row)
        return row
    }

    private func collection(_ name: String, _ index: Int, in ctx: ModelContext) throws -> RecipeCollection {
        let collection = RecipeCollection(name: name)
        collection.uuid = try uuid(index)
        ctx.insert(collection)
        return collection
    }

    private func makeRecipe(oil: Ingredient, amount: Double = 100, in ctx: ModelContext) -> Recipe {
        let recipe = Recipe(name: "Castile")
        recipe.weightUnit = "g"
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

    /// What the detail screen runs on `.duplicatesMerged`: a fresh load, then
    /// the lye and neutraliser defaults from its `@Query` results — which have
    /// not caught up with the merge yet and still hold the copies it deleted.
    @Test func reload_AfterMergeWithInventoryFromBeforeIt_LandsOnTheSurvivors() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let lyes = IngredientCategory(name: IngredientCategory.Name.lyes)
        let additives = IngredientCategory(name: IngredientCategory.Name.additives)
        ctx.insert(lyes)
        ctx.insert(additives)
        let keepOil = try installed("olive-oil", 1, in: ctx)
        let capturedOil = try installed("olive-oil", 2, in: ctx)
        let keepLye = try installed("sodium-hydroxide", 3, category: lyes, in: ctx)
        let capturedLye = try installed("sodium-hydroxide", 4, category: lyes, in: ctx)
        let boric = CFMNeutralizer.boricAcid.librarySlug
        let keepBoric = try installed(boric, 5, category: additives, in: ctx)
        let capturedBoric = try installed(boric, 6, category: additives, in: ctx)
        let recipe = makeRecipe(oil: capturedOil, in: ctx)
        try ctx.save()
        let lyesBeforeMerge = [capturedLye, keepLye]
        let additivesBeforeMerge = [capturedBoric, keepBoric]
        let model = loadedModel(from: recipe)

        try DuplicateMerger.mergeAll(in: ctx)
        model.load(from: recipe)
        model.resolveDefaultLyeIngredient(from: lyesBeforeMerge)
        model.resolveDefaultNeutralizerIngredient(from: additivesBeforeMerge)

        #expect(model.oilDrafts.map(\.ingredient) == [keepOil])
        #expect(model.lyeIngredient === keepLye)
        #expect(model.neutralizerIngredient === keepBoric)
        #expect(RecipeStats(oilDrafts: model.oilDrafts).hasFattyAcidData)
    }

    // MARK: - Open form: ingredients

    @Test func resolveMergedRows_OilMergedAway_DraftMovesOntoTheSurvivorKeepingItsRow() throws {
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
        model.resolveMergedRows(in: ctx)

        let draft = try #require(model.oilDrafts.first)
        #expect(model.oilDrafts.count == 1)
        #expect(draft.ingredient === keep)
        #expect(draft.id == draftID)
        #expect(draft.amount == 70)
        #expect(RecipeStats(oilDrafts: model.oilDrafts).hasFattyAcidData)
    }

    /// A merge isn't an edit, so it must not leave the form asking to discard.
    @Test func resolveMergedRows_UneditedForm_StaysClean() throws {
        let (container, ctx) = try makeContext()
        _ = container
        _ = try installed("olive-oil", 1, in: ctx)
        let capturedOil = try installed("olive-oil", 2, in: ctx)
        _ = try installed("sodium-hydroxide", 3, in: ctx)
        let capturedLye = try installed("sodium-hydroxide", 4, in: ctx)
        let recipe = makeRecipe(oil: capturedOil, in: ctx)
        recipe.lyeIngredient = capturedLye
        try ctx.save()
        let model = loadedModel(from: recipe)

        try DuplicateMerger.mergeAll(in: ctx)
        model.resolveMergedRows(in: ctx)

        #expect(!model.isDirty)
    }

    /// The baseline follows the merge without swallowing an ingredient the user
    /// added before it.
    @Test func resolveMergedRows_OilAddedBeforeTheMerge_StaysDirty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        _ = try installed("olive-oil", 1, in: ctx)
        let captured = try installed("olive-oil", 2, in: ctx)
        let coconut = try installed("coconut-oil", 3, in: ctx)
        let recipe = makeRecipe(oil: captured, in: ctx)
        try ctx.save()
        let model = loadedModel(from: recipe)
        model.addOil(coconut)

        try DuplicateMerger.mergeAll(in: ctx)
        model.resolveMergedRows(in: ctx)

        #expect(model.oilDrafts.count == 2)
        #expect(model.isDirty)
    }

    @Test func resolveMergedRows_AdditiveAndFragranceMergedAway_BothMoveOntoTheSurvivors() throws {
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
        model.resolveMergedRows(in: ctx)

        #expect(model.additiveDrafts.map(\.ingredient) == [keepSugar])
        #expect(model.fragranceDrafts.map(\.ingredient) == [keepLavender])
        #expect(model.additiveDrafts.first?.amount == 10)
    }

    @Test func resolveMergedRows_BothLyesAndNeutralizerMergedAway_MoveOntoTheSurvivors() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = try installed("olive-oil", 1, in: ctx)
        let keepNaOH = try installed("sodium-hydroxide", 2, in: ctx)
        let capturedNaOH = try installed("sodium-hydroxide", 3, in: ctx)
        let keepKOH = try installed("potassium-hydroxide", 4, in: ctx)
        let capturedKOH = try installed("potassium-hydroxide", 5, in: ctx)
        let keepBoric = try installed("boric-acid", 6, in: ctx)
        let capturedBoric = try installed("boric-acid", 7, in: ctx)
        let recipe = makeRecipe(oil: oil, in: ctx)
        recipe.lyeIngredient = capturedNaOH
        recipe.kohLyeIngredient = capturedKOH
        recipe.neutralizerIngredient = capturedBoric
        try ctx.save()
        let model = loadedModel(from: recipe)

        try DuplicateMerger.mergeAll(in: ctx)
        model.resolveMergedRows(in: ctx)

        #expect(model.lyeIngredient === keepNaOH)
        #expect(model.kohLyeIngredient === keepKOH)
        #expect(model.neutralizerIngredient === keepBoric)
        #expect(!model.isDirty)
    }

    /// The user swapped the lye, and then the merge deleted the one the recipe
    /// was saved with. The baseline has no slug for it, so it is cleared rather
    /// than compared while detached, and the swap still counts as an edit.
    @Test func resolveMergedRows_ReplacedLyeMergedAway_StaysDirtyWithoutReadingIt() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = try installed("olive-oil", 1, in: ctx)
        _ = try installed("sodium-hydroxide", 2, in: ctx)
        let savedLye = try installed("sodium-hydroxide", 3, in: ctx)
        let chosenLye = try installed("potassium-hydroxide", 4, in: ctx)
        let recipe = makeRecipe(oil: oil, in: ctx)
        recipe.lyeIngredient = savedLye
        try ctx.save()
        let model = loadedModel(from: recipe)
        model.lyeIngredient = chosenLye

        try DuplicateMerger.mergeAll(in: ctx)
        #expect(savedLye.modelContext == nil)
        model.resolveMergedRows(in: ctx)

        #expect(model.lyeIngredient === chosenLye)
        #expect(model.isDirty)
    }

    /// No survivor to move onto: the row goes rather than staying on a deleted
    /// ingredient the next redraw would read.
    @Test func resolveMergedRows_UserOilDeletedOutright_DraftIsDropped() throws {
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
        model.resolveMergedRows(in: ctx)

        #expect(model.oilDrafts.map(\.ingredient) == [kept])
    }

    /// The ordinary path, so the tests above cannot pass by rebuilding rows that
    /// had nothing wrong with them.
    @Test func resolveMergedRows_NothingMerged_LeavesEveryRowAsItWas() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = try installed("olive-oil", 1, in: ctx)
        let lye = try installed("sodium-hydroxide", 2, in: ctx)
        let gifts = try collection("Gifts", 3, in: ctx)
        let recipe = makeRecipe(oil: oil, amount: 55, in: ctx)
        recipe.lyeIngredient = lye
        recipe.collections = [gifts]
        try ctx.save()
        let model = loadedModel(from: recipe)
        let before = model.oilDrafts

        model.resolveMergedRows(in: ctx)

        #expect(model.oilDrafts == before)
        #expect(model.lyeIngredient === lye)
        #expect(model.selectedCollections == [gifts])
        #expect(!model.isDirty)
    }

    // MARK: - Open form: collections

    @Test func resolveMergedRows_CollectionMergedAway_MovesOntoTheSurvivorAndStaysClean() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = try installed("olive-oil", 1, in: ctx)
        let keep = try collection("Gifts", 2, in: ctx)
        let captured = try collection("gifts ", 3, in: ctx)
        let recipe = makeRecipe(oil: oil, in: ctx)
        recipe.collections = [captured]
        try ctx.save()
        let model = loadedModel(from: recipe)

        try DuplicateMerger.mergeAll(in: ctx)
        #expect(captured.modelContext == nil)
        model.resolveMergedRows(in: ctx)

        #expect(model.selectedCollections == [keep])
        #expect(model.collectionsLabel == keep.name)
        #expect(!model.isDirty)
    }

    /// Both copies were ticked, so the survivor is listed once rather than twice.
    @Test func resolveMergedRows_BothCopiesOfACollectionSelected_SurvivorListedOnce() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = try installed("olive-oil", 1, in: ctx)
        let keep = try collection("Gifts", 2, in: ctx)
        let captured = try collection("Gifts", 3, in: ctx)
        let recipe = makeRecipe(oil: oil, in: ctx)
        try ctx.save()
        let model = loadedModel(from: recipe)
        model.toggleCollection(keep)
        model.toggleCollection(captured)

        try DuplicateMerger.mergeAll(in: ctx)
        model.resolveMergedRows(in: ctx)

        #expect(model.selectedCollections == [keep])
    }

    // MARK: - Create Batch sheet

    /// The sheet keeps its own working copy of the recipe. Left on the merged-away
    /// oil, `requirements` reads it on the next render, and a batch created from
    /// it would be recorded against a row that no longer exists.
    @Test func batchSheet_OilMergedAway_RequirementsMoveOntoTheSurvivor() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installed("olive-oil", 1, in: ctx)
        let captured = try installed("olive-oil", 2, in: ctx)
        let recipe = makeRecipe(oil: captured, amount: 500, in: ctx)
        try ctx.save()
        let sheet = BatchProductionViewModel(recipe: recipe, lyeCandidates: [])
        sheet.batchCount = 2

        try DuplicateMerger.mergeAll(in: ctx)
        sheet.resolveMergedRows(in: ctx)

        let requirement = try #require(sheet.requirements.first)
        #expect(sheet.requirements.count == 1)
        #expect(requirement.ingredient === keep)
        #expect(requirement.required == 1000)
        #expect(sheet.batchCount == 2)
    }
}
