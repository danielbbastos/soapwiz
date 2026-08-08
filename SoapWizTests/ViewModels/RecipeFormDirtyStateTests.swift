import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("RecipeForm – unsaved changes", .serialized)
@MainActor
struct RecipeFormDirtyStateTests: RecipeFormTestHelpers {

    // MARK: - Baseline

    @Test func isDirty_NoSnapshotCaptured_IsFalse() {
        let model = RecipeFormViewModel()
        model.name = "Edited before the form finished loading"

        #expect(model.isDirty == false)
    }

    @Test func isDirty_NewFormUntouched_IsFalse() {
        let model = RecipeFormViewModel()
        model.captureSnapshot()

        #expect(model.isDirty == false)
    }

    @Test func isDirty_LoadedRecipeUntouched_IsFalse() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = try makeStoredRecipe(in: ctx)

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        model.captureSnapshot()

        #expect(model.isDirty == false)
    }

    @Test func isDirty_SnapshotRecapturedAfterEdit_IsFalseAgain() {
        let model = RecipeFormViewModel()
        model.captureSnapshot()
        model.name = "Castile"

        model.captureSnapshot()

        #expect(model.isDirty == false)
    }

    // MARK: - Scalar fields

    @Test(arguments: [
        ("name", { (model: RecipeFormViewModel) in model.name = "Castile" }),
        ("desc", { model in model.desc = "A gentle bar" }),
        ("weightUnit", { model in model.weightUnit = "g" }),
        ("totalOilWeight", { model in model.totalOilWeight = 2000 }),
        ("oilWeightUnit", { model in model.oilWeightUnit = "kg" }),
        ("lyeType", { model in model.lyeType = "KOH" }),
        ("lyePurity", { model in model.lyePurity = 95 }),
        ("waterParts", { model in model.waterParts = 2 }),
        ("superFat", { model in model.superFat = 8 }),
        ("fragrancePercentage", { model in model.fragrancePercentage = 5 }),
        ("useHybrid", { model in model.useHybrid = true }),
        ("kohPercentage", { model in model.kohPercentage = 70 }),
        ("naohPercentage", { model in model.naohPercentage = 30 }),
        ("kohPurity", { model in model.kohPurity = 85 }),
        ("naohPurity", { model in model.naohPurity = 97 }),
        ("isCreamSoap", { model in model.isCreamSoap = true }),
        ("useCFM", { model in model.useCFM = true }),
        ("cfmNeutralizer", { model in model.cfmNeutralizer = .borax })
    ] as [(String, (RecipeFormViewModel) -> Void)])
    func isDirty_ScalarFieldChanged_IsTrue(field: String, edit: (RecipeFormViewModel) -> Void) {
        let model = RecipeFormViewModel()
        model.captureSnapshot()

        edit(model)

        #expect(model.isDirty, "changing \(field) should mark the form dirty")
    }

    // MARK: - Draft rows

    @Test func isDirty_OilAdded_IsTrue() {
        let model = RecipeFormViewModel()
        model.captureSnapshot()

        model.addOil(Ingredient(name: "Olive Oil"))

        #expect(model.isDirty)
    }

    @Test func isDirty_OilRemoved_IsTrue() {
        let model = RecipeFormViewModel()
        model.addOil(Ingredient(name: "Olive Oil"))
        model.captureSnapshot()

        model.removeOil(at: IndexSet(integer: 0))

        #expect(model.isDirty)
    }

    @Test func isDirty_OilAmountEdited_IsTrue() {
        let model = RecipeFormViewModel()
        model.weightUnit = "g"
        model.addOil(Ingredient(name: "Olive Oil"))
        model.captureSnapshot()

        model.userEdited(id: model.oilDrafts[0].id, amount: 42)

        #expect(model.isDirty)
    }

    @Test func isDirty_AdditiveAdded_IsTrue() {
        let model = RecipeFormViewModel()
        model.captureSnapshot()

        model.addAdditive(Ingredient(name: "Sodium Lactate"))

        #expect(model.isDirty)
    }

    @Test func isDirty_AdditiveUnitChanged_IsTrue() {
        let model = RecipeFormViewModel()
        model.addAdditive(Ingredient(name: "Sodium Lactate"))
        model.captureSnapshot()

        model.updateAdditive(id: model.additiveDrafts[0].id, unit: "ml")

        #expect(model.isDirty)
    }

    @Test func isDirty_FragranceAdded_IsTrue() {
        let model = RecipeFormViewModel()
        model.captureSnapshot()

        model.addFragrance(Ingredient(name: "Lavender EO"))

        #expect(model.isDirty)
    }

    @Test func isDirty_FragranceUnitChanged_IsTrue() {
        let model = RecipeFormViewModel()
        model.captureSnapshot()

        model.setFragranceUnit(.grams)

        #expect(model.isDirty)
    }

    @Test func isDirty_ProductAdded_IsTrue() {
        let model = RecipeFormViewModel()
        model.captureSnapshot()

        model.addProduct(defaultUnitSymbol: ProductUnit.grams.rawValue)

        #expect(model.isDirty)
    }

    @Test func isDirty_ProductSizeEdited_IsTrue() {
        let model = RecipeFormViewModel()
        model.captureSnapshot()

        model.productDrafts[0].size = 120

        #expect(model.isDirty)
    }

    // MARK: - Lye ingredient resolution

    @Test func isDirty_LyeResolvedAfterCapture_StaysFalse() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let lyes = try makeLyeInventory(in: ctx)

        let model = RecipeFormViewModel()
        model.captureSnapshot()
        // Mirrors a CloudKit arrival: the form is already on screen and untouched
        // when the lye inventory shows up and the defaults resolve.
        model.resolveDefaultLyeIngredient(from: lyes)

        #expect(model.lyeIngredient != nil)
        #expect(model.kohLyeIngredient != nil)
        #expect(model.isDirty == false)
    }

    @Test func isDirty_LyeIngredientChangedByUser_IsTrue() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let lyes = try makeLyeInventory(in: ctx)

        let model = RecipeFormViewModel()
        model.resolveDefaultLyeIngredient(from: lyes)
        model.captureSnapshot()

        let other = try #require(lyes.first { $0 !== model.lyeIngredient })
        model.lyeIngredient = other

        #expect(model.isDirty)
    }

    // MARK: - Seeded and imported forms

    @Test func isDirty_SeedAppliedAfterCapture_IsTrue() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let category = IngredientCategory(name: IngredientCategory.Name.oils)
        ctx.insert(category)
        let oil = Ingredient(name: "Olive Oil")
        oil.category = category
        ctx.insert(oil)

        let model = RecipeFormViewModel()
        model.captureSnapshot()
        model.applySeed([oil])

        #expect(model.oilDrafts.count == 1)
        #expect(model.isDirty)
    }

    // MARK: - Reloading straight after a save

    /// The detail screen re-reads the recipe the moment the edit form saves and
    /// pops. Deleted line items linger in the relationship until the context
    /// processes them, so without that the reload sees every row twice.
    @Test func load_ImmediatelyAfterSave_DoesNotDuplicateRows() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let recipe = try makeStoredRecipe(in: ctx)
        let oil = Ingredient(name: "Olive Oil")
        let fragrance = Ingredient(name: "Lavender EO")
        let additive = Ingredient(name: "Sodium Lactate")
        [oil, fragrance, additive].forEach { ctx.insert($0) }
        try ctx.save()

        let model = RecipeFormViewModel()
        model.load(from: recipe)
        model.addOil(oil)
        model.addFragrance(fragrance)
        model.addAdditive(additive)
        model.save(context: ctx)

        // A second round trip: the first save's rows are the ones now being replaced.
        model.save(context: ctx)
        model.load(from: recipe)

        #expect(model.oilDrafts.count == 1)
        #expect(model.fragranceDrafts.count == 1)
        #expect(model.additiveDrafts.count == 1)
        #expect(model.productDrafts.count == 1)
    }

    // MARK: - Helpers

    private func makeStoredRecipe(in ctx: ModelContext) throws -> Recipe {
        let recipe = Recipe(name: "Bastille", desc: "Olive-heavy bar")
        recipe.weightUnit = "%"
        recipe.totalOilWeight = 1000
        recipe.superFat = 5
        recipe.useCFM = false
        ctx.insert(recipe)
        try ctx.save()
        return recipe
    }

    private func makeLyeInventory(in ctx: ModelContext) throws -> [Ingredient] {
        let category = IngredientCategory(name: IngredientCategory.Name.lyes)
        ctx.insert(category)
        let names = ["Sodium Hydroxide (Lye)", "Potassium Hydroxide (Lye)"]
        let ingredients = names.map { name -> Ingredient in
            let ingredient = Ingredient(name: name)
            ingredient.category = category
            ctx.insert(ingredient)
            return ingredient
        }
        try ctx.save()
        return ingredients
    }
}
