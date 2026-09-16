import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The recipe form carries the same stale-reference exposure as the purchase
/// sheet: its drafts hold `Ingredient` references captured when the row was
/// added, and the duplicate merge can delete one before the user taps Save.
///
/// `Ingredient.recipeIngredients` cascades, so a line item written against a
/// detached row would be deleted along with it — the recipe would silently lose
/// an oil. Unlike a purchase there is a safe degraded shape available: a line
/// item with no ingredient is something sync already produces, and the form
/// counts those into `unresolvedLineItemCount` and shows them.
@Suite("Recipe form — stale ingredient references", .serialized)
@MainActor
struct RecipeFormStaleIngredientTests {

    /// The full schema, not the recipe-only one the other recipe suites use:
    /// `DuplicateMerger` fetches providers, storage locations and settings too.
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

    private func installed(_ index: Int, in ctx: ModelContext) throws -> Ingredient {
        let row = Ingredient(name: "Olive Oil", unit: IngredientUnit.grams.rawValue)
        row.librarySlug = "olive-oil"
        row.sapValue = 0.135
        row.uuid = try uuid(index)
        ctx.insert(row)
        return row
    }

    private func makeModel(addingOil oil: Ingredient) -> RecipeFormViewModel {
        let model = RecipeFormViewModel()
        model.name = "Castile"
        model.weightUnit = "%"
        model.oilWeightUnit = "g"
        model.totalOilWeight = 1000
        model.addOil(oil)
        return model
    }

    /// The form was opened on the copy the merge then deleted. The line item has
    /// to land on the survivor, not on the row that is gone.
    @Test func save_AfterMergeDeletedADraftIngredient_LineItemPointsAtTheSurvivor() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installed(1, in: ctx)
        let captured = try installed(2, in: ctx)
        try ctx.save()
        let survivingUUID = keep.uuid

        let model = makeModel(addingOil: captured)

        try DuplicateMerger.mergeAll(in: ctx)
        #expect(captured.modelContext == nil)

        let recipe = model.save(context: ctx)
        try ctx.save()

        #expect(recipe.ingredients.count == 1)
        #expect(recipe.ingredients.first?.ingredient?.uuid == survivingUUID)
    }

    /// No survivor to resolve to. The line item is written with no ingredient —
    /// a shape the recipe already tolerates — rather than against a detached row
    /// the next save would cascade away.
    @Test func save_DraftIngredientDeletedWithNoSurvivor_WritesAnUnresolvedLineItem() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let userRow = Ingredient(name: "Kokum Butter", unit: IngredientUnit.grams.rawValue)
        userRow.uuid = try uuid(1)
        ctx.insert(userRow)
        try ctx.save()

        let model = makeModel(addingOil: userRow)

        ctx.delete(userRow)
        try ctx.save()

        let recipe = model.save(context: ctx)
        try ctx.save()

        #expect(recipe.ingredients.count == 1)
        #expect(recipe.ingredients.first?.ingredient == nil)
    }

    // MARK: - Lye rows

    /// The lye rows are captured the same way the drafts are, and the merge
    /// repoints the stored recipe onto the survivor before deleting the copy the
    /// form holds. Writing the captured reference back on save would undo that
    /// repoint and leave the recipe's lye pointing at a row that is gone.
    @Test func save_AfterMergeDeletedTheLyeIngredient_RecipePointsAtTheSurvivor() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installed(1, in: ctx)
        let captured = try installed(2, in: ctx)
        try ctx.save()
        let survivingUUID = keep.uuid

        let model = makeModel(addingOil: keep)
        model.lyeIngredient = captured

        try DuplicateMerger.mergeAll(in: ctx)
        #expect(captured.modelContext == nil)

        let recipe = model.save(context: ctx)
        try ctx.save()

        #expect(recipe.lyeIngredient?.uuid == survivingUUID)
    }

    /// No survivor to resolve to. `Recipe.lyeIngredient` nullifies, so the link
    /// is cleared rather than written against a row the store no longer has.
    @Test func save_LyeIngredientDeletedWithNoSurvivor_ClearsTheLink() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = try installed(1, in: ctx)
        let userLye = Ingredient(name: "Sodium Hydroxide", unit: IngredientUnit.grams.rawValue)
        userLye.uuid = try uuid(2)
        ctx.insert(userLye)
        try ctx.save()

        let model = makeModel(addingOil: oil)
        model.lyeIngredient = userLye

        ctx.delete(userLye)
        try ctx.save()

        let recipe = model.save(context: ctx)
        try ctx.save()

        #expect(recipe.lyeIngredient == nil)
    }

    /// The ordinary path for both lye rows, so the guards above cannot pass by
    /// clearing every lye link.
    @Test func save_LyeIngredientsStillInTheStore_BothLinksPointAtThem() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = try installed(1, in: ctx)
        let naoh = Ingredient(name: "Sodium Hydroxide", unit: IngredientUnit.grams.rawValue)
        naoh.uuid = try uuid(2)
        let koh = Ingredient(name: "Potassium Hydroxide", unit: IngredientUnit.grams.rawValue)
        koh.uuid = try uuid(3)
        ctx.insert(naoh)
        ctx.insert(koh)
        try ctx.save()

        let model = makeModel(addingOil: oil)
        model.lyeIngredient = naoh
        model.kohLyeIngredient = koh

        let recipe = model.save(context: ctx)
        try ctx.save()

        #expect(recipe.lyeIngredient?.uuid == naoh.uuid)
        #expect(recipe.kohLyeIngredient?.uuid == koh.uuid)
    }

    // MARK: - Line items

    /// The ordinary path, so the guards above cannot pass by dropping every
    /// ingredient.
    @Test func save_DraftIngredientStillInTheStore_LineItemPointsAtIt() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = try installed(1, in: ctx)
        try ctx.save()

        let model = makeModel(addingOil: oil)
        let recipe = model.save(context: ctx)
        try ctx.save()

        #expect(recipe.ingredients.count == 1)
        #expect(recipe.ingredients.first?.ingredient?.uuid == oil.uuid)
    }
}
