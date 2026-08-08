import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("RecipeForm – recipe-wide fragrance unit", .serialized)
@MainActor
struct RecipeFragranceUnitTests: RecipeFormTestHelpers {

    /// 1000 g of oils, 3% fragrance load, two fragrances in `% of fragrances`
    /// mode holding a 60/40 blend.
    private func makeBlendModel() -> RecipeFormViewModel {
        let model = RecipeFormViewModel()
        model.weightUnit = "%"
        model.oilWeightUnit = "g"
        model.totalOilWeight = 1000
        model.fragrancePercentage = 3
        model.addOil(Ingredient(name: "Olive Oil"))
        model.setFragranceUnit(.percentOfFragrances)
        model.addFragrance(Ingredient(name: "Lavender EO"))
        model.addFragrance(Ingredient(name: "Cedarwood EO"))
        model.userEditedFragrance(id: model.fragranceDrafts[0].id, amount: 60)
        return model
    }

    // A recipe built outside the form — seeded, restored, or CloudKit-synced —
    // must come back as `% of oils`, which is a separate question from what a
    // new form offers.
    @Test func recipe_SchemaDefault_IsPercentOfOils() {
        #expect(Recipe(name: "New").fragranceUnit == FragranceUnit.percentOfOils.rawValue)
    }

    // MARK: - % of fragrances resolution

    @Test func percentOfFragrances_ResolvesSharesAgainstTheLoad() throws {
        let model = makeBlendModel()
        #expect(model.fragranceDrafts.map(\.amount) == [60, 40])

        let rows = model.wholeBatchBreakdown.fragrances
        // 3% of 1000 g = 30 g load; 60/40 → 18 g and 12 g.
        #expect(rows.count == 2)
        #expect(abs(rows[0].ingredientAmount - 18) < 1e-6)
        #expect(abs(rows[1].ingredientAmount - 12) < 1e-6)
    }

    @Test func percentOfFragrances_LoadChange_KeepsBlendRatios() throws {
        let model = makeBlendModel()

        model.fragrancePercentage = 5

        // The blend stays 60/40; only the absolute weights scale: 50 g load.
        #expect(model.fragranceDrafts.map(\.amount) == [60, 40])
        let rows = model.wholeBatchBreakdown.fragrances
        #expect(abs(rows[0].ingredientAmount - 30) < 1e-6)
        #expect(abs(rows[1].ingredientAmount - 20) < 1e-6)
    }

    @Test func percentOfFragrances_RowsNotSumming100_ResolveProportionally() throws {
        let model = makeBlendModel()
        model.fragranceDrafts[0].amount = 30
        model.fragranceDrafts[1].amount = 30

        // Shares are normalised by their actual sum (60), not an assumed 100,
        // so the 30 g load still splits fully: 15 g each.
        let rows = model.wholeBatchBreakdown.fragrances
        #expect(abs(rows[0].ingredientAmount - 15) < 1e-6)
        #expect(abs(rows[1].ingredientAmount - 15) < 1e-6)
    }

    @Test func percentOfFragrances_ZeroLoad_ResolvesNoRows() {
        let model = makeBlendModel()
        model.fragrancePercentage = 0
        #expect(model.wholeBatchBreakdown.fragrances.isEmpty)
    }

    // MARK: - Switching units

    @Test func setFragranceUnit_ToPercentOfFragrances_PreservesRatios() {
        let model = RecipeFormViewModel()
        model.weightUnit = "g"
        model.setFragranceUnit(.grams)
        model.addFragrance(Ingredient(name: "Lavender EO"))
        model.addFragrance(Ingredient(name: "Cedarwood EO"))
        model.userEditedFragrance(id: model.fragranceDrafts[0].id, amount: 18)
        model.userEditedFragrance(id: model.fragranceDrafts[1].id, amount: 12)

        model.setFragranceUnit(.percentOfFragrances)

        #expect(model.fragranceDrafts.map(\.amount) == [60, 40])
    }

    @Test func setFragranceUnit_ToPercentOfFragrances_AllZero_SplitsEvenly() {
        let model = RecipeFormViewModel()
        model.weightUnit = "g"
        model.setFragranceUnit(.grams)
        model.addFragrance(Ingredient(name: "Lavender EO"))
        model.addFragrance(Ingredient(name: "Cedarwood EO"))

        model.setFragranceUnit(.percentOfFragrances)

        #expect(model.fragranceDrafts.map(\.amount) == [50, 50])
    }

    @Test func setFragranceUnit_ToMassUnit_KeepsAmounts() {
        let model = makeBlendModel()

        model.setFragranceUnit(.grams)

        #expect(model.fragranceDrafts.map(\.amount) == [60, 40])
        #expect(model.fragranceDrafts.allSatisfy { $0.unit == "g" })
    }

    // MARK: - Blend total

    @Test func fragranceBlendTotal_PercentOfFragrancesMode_SumsShares() {
        let model = makeBlendModel()
        #expect(model.fragranceBlendTotal == 100)

        model.fragranceDrafts[1].amount = 25
        #expect(model.fragranceBlendTotal == 85)
    }

    @Test func fragranceBlendTotal_OtherUnits_IsNil() {
        let model = makeModelWithOilsAndFragrance(fragranceUnit: .grams)
        #expect(model.fragranceBlendTotal == nil)
    }

    @Test func fragranceBlendTotal_NoFragrances_IsNil() {
        let model = RecipeFormViewModel()
        model.setFragranceUnit(.percentOfFragrances)
        #expect(model.fragranceBlendTotal == nil)
    }

    // MARK: - Loading a stored recipe

    private func makeStoredRecipe(
        _ ctx: ModelContext,
        unit: FragranceUnit = .percentOfOils,
        rowUnits: [(amount: Double, unit: String)]
    ) -> Recipe {
        let recipe = Recipe(name: "Stored", desc: "")
        recipe.weightUnit = "%"
        recipe.totalOilWeight = 1000
        recipe.oilWeightUnit = "g"
        recipe.fragrancePercentage = 3
        recipe.fragranceUnit = unit.rawValue
        ctx.insert(recipe)
        for (index, row) in rowUnits.enumerated() {
            let ingredient = Ingredient(name: "Fragrance \(index)")
            ctx.insert(ingredient)
            let line = RecipeIngredient(ingredient: ingredient, percentage: 0, role: .fragrance)
            line.additiveAmount = row.amount
            line.additiveUnit = row.unit
            line.recipe = recipe
            ctx.insert(line)
        }
        ctx.processPendingChanges()
        return recipe
    }

    @Test func load_AgreedRows_KeepsUnitsAndAmounts() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeStoredRecipe(ctx, rowUnits: [(2.5, "% of oils"), (0.5, "% of oils")])

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.fragranceUnit == .percentOfOils)
        #expect(Set(model.fragranceDrafts.map(\.amount)) == [2.5, 0.5])
    }

    @Test func load_StoredRecipeUnitWins_RowUnitIsIgnored() throws {
        let (container, ctx) = try makeContext()
        _ = container
        // The unit is one per recipe, so the row's own unit string carries no
        // authority — the amount is read against the recipe's unit.
        let recipe = makeStoredRecipe(ctx, unit: .percentOfOils, rowUnits: [(2.5, "g")])

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.fragranceUnit == .percentOfOils)
        #expect(model.fragranceDrafts.map(\.unit) == ["% of oils"])
        #expect(model.fragranceDrafts.map(\.amount) == [2.5])
    }

    @Test func load_UnrecognisedRecipeUnit_FallsBackToPercentOfOils() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeStoredRecipe(ctx, rowUnits: [(2, "% of oils")])
        recipe.fragranceUnit = "kg"

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.fragranceUnit == .percentOfOils)
        #expect(model.fragranceDrafts.map(\.unit) == ["% of oils"])
        #expect(model.fragranceDrafts.map(\.amount) == [2])
    }

    @Test func load_MassUnit_LeavesRowsUnlocked() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeStoredRecipe(ctx, unit: .grams, rowUnits: [(20, "g"), (5, "g")])

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        // A mass unit has no budget to spread, so there is nothing for a lock to
        // protect the amounts from.
        #expect(model.fragranceDrafts.allSatisfy { !$0.isLocked })
        #expect(Set(model.fragranceDrafts.map(\.amount)) == [20, 5])
    }

    @Test func load_RedistributingUnit_LocksEveryRow() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeStoredRecipe(
            ctx,
            unit: .percentOfFragrances,
            rowUnits: [(60, "% of fragrances"), (40, "% of fragrances")]
        )

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.fragranceDrafts.allSatisfy { $0.isLocked })
        #expect(Set(model.fragranceDrafts.map(\.amount)) == [60, 40])
    }

    @Test func load_NoFragranceRows_UsesTheStoredRecipeUnit() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeStoredRecipe(ctx, rowUnits: [])
        recipe.fragranceUnit = FragranceUnit.percentOfFragrances.rawValue

        let model = RecipeFormViewModel()
        model.load(from: recipe)

        #expect(model.fragranceUnit == .percentOfFragrances)
    }

    // MARK: - Editing a saved recipe vs. creating one

    @Test func addFragrance_NewRecipe_SplitsTheBlendAfresh() {
        let model = RecipeFormViewModel()
        model.addFragrance(Ingredient(name: "A"))
        model.addFragrance(Ingredient(name: "B"))
        model.addFragrance(Ingredient(name: "C"))

        // Nothing is the user's saved work yet, so each row splits the total.
        // The last row carries the rounding remainder, so this is a near-third
        // each rather than three equal values.
        let amounts = model.fragranceDrafts.map(\.amount)
        #expect(amounts.count == 3)
        #expect(amounts.allSatisfy { abs($0 - 100 / 3) < 0.1 })
        #expect(abs(amounts.reduce(0, +) - 100) < 1e-9)
    }

    @Test func addFragrance_SavedRecipe_StartsAtZeroAndKeepsTheSavedBlend() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeStoredRecipe(ctx, unit: .percentOfFragrances, rowUnits: [
            (60, "% of fragrances"), (40, "% of fragrances")
        ])

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        model.addFragrance(Ingredient(name: "Third EO"))

        #expect(model.fragranceDrafts.map(\.amount) == [60, 40, 0])
    }

    @Test func addFragrance_SavedRecipe_ThenEditingASavedRowFeedsTheNewOne() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeStoredRecipe(ctx, unit: .percentOfFragrances, rowUnits: [
            (60, "% of fragrances"), (40, "% of fragrances")
        ])

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        model.addFragrance(Ingredient(name: "Third EO"))
        model.userEditedFragrance(id: model.fragranceDrafts[0].id, amount: 50)

        // The slack freed by the edit goes to the row still unspoken for.
        #expect(model.fragranceDrafts.map(\.amount) == [50, 40, 10])
    }

    @Test func removeFragrance_SavedRecipe_LeavesTheOtherAmountsAlone() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeStoredRecipe(ctx, unit: .percentOfFragrances, rowUnits: [
            (60, "% of fragrances"), (40, "% of fragrances")
        ])

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        model.removeFragrance(at: IndexSet(integer: 1))

        // The survivor keeps the number the user saved; the shares now total 60,
        // which `fragranceBlendTotal` surfaces rather than silently rewriting.
        #expect(model.fragranceDrafts.map(\.amount) == [60])
        #expect(model.fragranceBlendTotal == 60)
    }

    @Test func load_SavedPercentOfOilsRecipe_AlsoLocksItsRows() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeStoredRecipe(ctx, rowUnits: [(2, "% of oils"), (1, "% of oils")])

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        model.addFragrance(Ingredient(name: "Third EO"))

        // Same rule in the other redistributing unit: the saved 2/1 against a
        // 3% load leaves nothing for the new row.
        #expect(model.fragranceDrafts.map(\.amount) == [2, 1, 0])
    }

    @Test func load_ThenCaptureSnapshot_StampingAloneIsNotDirty() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeStoredRecipe(ctx, unit: .grams, rowUnits: [(20, "g"), (5, "g")])

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        model.captureSnapshot()

        #expect(!model.isDirty)
    }

    // MARK: - Save

    @Test func save_StampsRecipeUnitAndEveryFragranceRow() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = makeStoredRecipe(ctx, unit: .grams, rowUnits: [(20, "g"), (5, "g")])

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        model.name = "Renamed"
        model.save(context: ctx)

        #expect(recipe.fragranceUnit == FragranceUnit.grams.rawValue)
        let fragranceRows = recipe.ingredients.filter { $0.ingredientRole == .fragrance }
        #expect(fragranceRows.count == 2)
        #expect(fragranceRows.allSatisfy { $0.additiveUnit == "g" })
    }
}
