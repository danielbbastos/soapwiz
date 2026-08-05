import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("Recipe import → recipe form", .serialized)
@MainActor
struct RecipeImportFormMappingTests: RecipeImportTestHelpers {

    /// Held for the lifetime of each test. A container that goes out of scope
    /// takes its models with it, and every `Ingredient` here has to outlive the
    /// call that created it.
    private let container: ModelContainer
    private let context: ModelContext
    private let inventory: [Ingredient]

    init() throws {
        let schema = Schema([
            Recipe.self, RecipeIngredient.self, RecipeProduct.self,
            Ingredient.self, IngredientPurchase.self, IngredientCategory.self
        ])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        context = container.mainContext
        inventory = Self.buildInventory(in: context)
    }

    // MARK: - Weight modes

    @Test func applyImport_PercentageRecipe_UsesPercentageMode() {
        let model = apply(.mock(amountsArePercentages: true, batchSize: 1_500, batchUnit: "g"))

        #expect(model.weightUnit == "%")
        #expect(model.weightUnitIsPercentage)
        #expect(model.oilWeightUnit == "g")
        #expect(model.totalOilWeight == 1_500)
    }

    @Test func applyImport_WeightRecipe_MeasuresInTheSourcesUnit() {
        let model = apply(.mock(
            oils: [
                ImportedIngredient(name: "Olive Oil", amount: 24, unit: "oz"),
                ImportedIngredient(name: "Coconut Oil", amount: 8, unit: "oz")
            ],
            amountsArePercentages: false,
            batchSize: nil,
            batchUnit: "oz"
        ))

        #expect(model.weightUnit == "oz")
        #expect(!model.weightUnitIsPercentage)
        #expect(model.oilDrafts.map(\.amount) == [24, 8])
    }

    @Test func applyImport_NoBatchSize_KeepsTheFormsDefault() {
        let defaultWeight = RecipeFormViewModel().totalOilWeight
        #expect(apply(.mock(batchSize: nil)).totalOilWeight == defaultWeight)
    }

    @Test func applyImport_UnsupportedUnit_FallsBackToGrams() {
        #expect(apply(.mock(batchUnit: "stone")).oilWeightUnit == "g")
    }

    // MARK: - Configuration

    @Test func applyImport_CopiesTheStatedLyeSettings() {
        let model = apply(.mock(lyeType: "NaOH", superFat: 8, waterParts: 2.5, fragrancePercentage: 4))

        #expect(model.lyeType == "NaOH")
        #expect(model.superFat == 8)
        #expect(model.waterParts == 2.5)
        #expect(model.fragrancePercentage == 4)
    }

    @Test func applyImport_KOH_MovesPurityToTheKOHDefault() {
        let model = apply(.mock(lyeType: "KOH"))
        #expect(model.lyeType == "KOH")
        #expect(model.lyePurity == RecipeFormViewModel.defaultKOHPurity)
    }

    /// A source that says nothing about superfat must not be read as saying 0%.
    @Test func applyImport_UnstatedSettings_KeepTheFormDefaults() {
        let defaults = RecipeFormViewModel()
        let model = apply(.mock(superFat: nil, waterParts: nil, fragrancePercentage: nil))

        #expect(model.superFat == defaults.superFat)
        #expect(model.waterParts == defaults.waterParts)
        #expect(model.fragrancePercentage == defaults.fragrancePercentage)
    }

    @Test func applyImport_CopiesTheName() {
        let model = apply(.mock(name: "Grandmother's Castile"))
        #expect(model.name == "Grandmother's Castile")
        #expect(model.canSave)
    }

    // MARK: - Ingredient rows

    @Test func applyImport_MatchedOils_KeepTheirExtractedAmounts() {
        let model = apply(.mock(oils: [
            ImportedIngredient(name: "Olive Oil", amount: 70, unit: nil),
            ImportedIngredient(name: "Coconut Oil", amount: 25, unit: nil),
            ImportedIngredient(name: "Castor Oil", amount: 5, unit: nil)
        ]))

        #expect(model.oilDrafts.count == 3)
        #expect(model.oilDrafts.map(\.amount) == [70, 25, 5])
        #expect(model.totalPercentage == 100)
    }

    @Test func applyImport_UnmatchedOil_IsNotAddedToTheForm() {
        let model = apply(.mock(oils: [
            ImportedIngredient(name: "Olive Oil", amount: 70, unit: nil),
            ImportedIngredient(name: "Unobtainium Oil", amount: 30, unit: nil)
        ]))

        #expect(model.oilDrafts.count == 1)
        #expect(model.oilDrafts.first?.ingredient.name == "Olive Oil")
    }

    @Test func applyImport_Fragrance_KeepsItsUnitAndAmount() throws {
        let model = apply(.mock(
            fragrances: [ImportedIngredient(name: "Lavender Essential Oil", amount: 30, unit: "g")]
        ))

        let fragrance = try #require(model.fragranceDrafts.first)
        #expect(fragrance.unit == "g")
        #expect(fragrance.amount == 30)
    }

    @Test func applyImport_FragranceWithAnUnofferedUnit_FallsBackToTheDefault() throws {
        let model = apply(.mock(
            fragrances: [ImportedIngredient(name: "Lavender Essential Oil", amount: 3, unit: "drops")]
        ))

        let fragrance = try #require(model.fragranceDrafts.first)
        #expect(RecipeUnitOptions.fragrance.contains(fragrance.unit))
    }

    @Test func applyImport_Additive_KeepsItsUnitAndAmount() throws {
        let clay = Ingredient(name: "Kaolin Clay", unit: "g")
        context.insert(clay)

        let draft = RecipeImportDraft.mock(additives: [ImportedIngredient(name: "Kaolin Clay", amount: 15, unit: "g")])
        let model = apply(draft, inventory: inventory + [clay])

        let additive = try #require(model.additiveDrafts.first)
        #expect(additive.amount == 15)
        #expect(additive.unit == "g")
    }

    @Test func applyImport_NoIngredients_LeavesTheFormEmptyButNamed() {
        let model = apply(.mock(name: "Empty", oils: []))
        #expect(model.oilDrafts.isEmpty)
        #expect(!model.hasIngredients)
        #expect(model.name == "Empty")
    }

    // MARK: - Bare percentages

    /// Sources write "1%", the pickers only offer the compound forms. Falling
    /// back to a weight would turn one percent of the oils into one gram.
    @Test func applyImport_AdditiveStatedAsABarePercentage_StaysAPercentage() throws {
        let clay = Ingredient(name: "Kaolin Clay", unit: "g")
        context.insert(clay)

        let draft = RecipeImportDraft.mock(additives: [ImportedIngredient(name: "Kaolin Clay", amount: 1, unit: "%")])
        let model = apply(draft, inventory: inventory + [clay])

        let additive = try #require(model.additiveDrafts.first)
        #expect(additive.unit == "% of oils")
        #expect(additive.amount == 1)
    }

    /// The fragrance case hides in a percentage-mode recipe, because the
    /// fallback there is already a percent unit. It only shows up when the
    /// recipe is measured in weights and the fragrance is still given as a
    /// percentage — a common combination.
    @Test func applyImport_FragranceBarePercentageInAWeightRecipe_StaysAPercentage() throws {
        let draft = RecipeImportDraft.mock(
            oils: [ImportedIngredient(name: "Olive Oil", amount: 700, unit: "g")],
            fragrances: [ImportedIngredient(name: "Lavender Essential Oil", amount: 3, unit: "%")],
            amountsArePercentages: false,
            batchSize: nil,
            batchUnit: "g"
        )
        let model = apply(draft)

        let fragrance = try #require(model.fragranceDrafts.first)
        #expect(fragrance.unit == "% of oils")
        #expect(fragrance.amount == 3)
    }

    @Test(arguments: ["%", "percent", "PCT", " % "])
    func applyImport_PercentSpellings_AllResolveToPercentOfOils(_ written: String) throws {
        let draft = RecipeImportDraft.mock(
            fragrances: [ImportedIngredient(name: "Lavender Essential Oil", amount: 3, unit: written)]
        )
        let model = apply(draft)
        #expect(model.fragranceDrafts.first?.unit == "% of oils")
    }

    /// An explicit base must survive untouched — the mapping is only for the
    /// bare case where the source said nothing.
    @Test func applyImport_ExplicitPercentBase_IsKept() throws {
        let clay = Ingredient(name: "Kaolin Clay", unit: "g")
        context.insert(clay)

        let draft = RecipeImportDraft.mock(
            additives: [ImportedIngredient(name: "Kaolin Clay", amount: 2, unit: "% of batch")]
        )
        let model = apply(draft, inventory: inventory + [clay])
        #expect(model.additiveDrafts.first?.unit == "% of batch")
    }

    /// A percentage that reaches the acid neutralisation must arrive as the
    /// share it was written as. Read as a weight it would move the lye.
    @Test func applyImport_AcidStatedAsAPercentage_KeepsItsShareOfTheOils() throws {
        let citric = Ingredient(name: "Citric Acid", unit: "g")
        context.insert(citric)

        let draft = RecipeImportDraft.mock(
            additives: [ImportedIngredient(name: "Citric Acid", amount: 2, unit: "%")],
            batchSize: 1_000
        )
        let model = apply(draft, inventory: inventory + [citric])

        let additive = try #require(model.additiveDrafts.first)
        #expect(additive.unit == "% of oils")
        // 2% of 1000 g of oils is 20 g of acid, not 2 g.
        let asWeight = IngredientUnitConverter.convert(
            additive.amount, from: additive.unit, to: "g", density: nil
        )
        #expect(asWeight == nil || asWeight?.value != 2)
    }

    // MARK: - Skipped rows

    @Test func applyImport_SkippedOil_IsRecordedInTheDescription() {
        let draft = RecipeImportDraft.mock(oils: [
            ImportedIngredient(name: "Olive Oil", amount: 85, unit: nil),
            ImportedIngredient(name: "Shea Butter", amount: 15, unit: nil)
        ])
        var rows = RecipeIngredientReconciler.reconcile(draft, against: inventory)
        rows[1].resolution = .skipped

        let model = RecipeFormViewModel()
        model.applyImport(PreparedRecipeImport(draft: draft, rows: rows))

        #expect(model.oilDrafts.count == 1)
        #expect(model.desc.contains("Not imported"))
        #expect(model.desc.contains("Shea Butter"))
        #expect(model.desc.contains("15"))
    }

    @Test func applyImport_NothingSkipped_LeavesTheDescriptionAlone() {
        #expect(!apply(.mock()).desc.contains("Not imported"))
    }

    // MARK: - Idempotence

    @Test func applyImport_CalledTwice_DoesNotDuplicateRows() {
        let draft = RecipeImportDraft.mock()
        let rows = RecipeIngredientReconciler.reconcile(draft, against: inventory)
        let prepared = PreparedRecipeImport(draft: draft, rows: rows)

        let model = RecipeFormViewModel()
        model.applyImport(prepared)
        model.applyImport(prepared)

        #expect(model.oilDrafts.count == 2)
    }

    // MARK: - Saving

    @Test func save_AfterAnImport_ProducesTheExpectedLyeWeight() throws {
        // 1000 g of oils: 700 g olive at 0.1345 + 300 g coconut at 0.1783,
        // 0% superfat at 100% purity → 94.15 + 53.49 = 147.64 g NaOH.
        let model = apply(.mock(
            oils: [
                ImportedIngredient(name: "Olive Oil", amount: 70, unit: nil),
                ImportedIngredient(name: "Coconut Oil", amount: 30, unit: nil)
            ],
            batchSize: 1_000,
            superFat: 0
        ))
        model.lyePurity = 100

        let lye = try #require(model.calculatedLyeAmount)
        #expect(abs(lye - 147.64) < 0.01)
    }

    @Test func save_AfterAnImport_WritesTheRecipe() throws {
        let model = apply(.mock(name: "Castile Bar"))

        let recipe = model.save(context: context)
        try context.save()

        #expect(recipe.name == "Castile Bar")
        #expect(recipe.ingredients.count == 2)
        #expect(try context.fetch(FetchDescriptor<Recipe>()).count == 1)
    }

    /// Nothing reaches the store until Save. Reviewing and applying an import
    /// leaves an abandoned attempt with no trace.
    @Test func applyImport_WithoutSaving_WritesNoRecipe() throws {
        _ = apply(.mock())

        #expect(try context.fetch(FetchDescriptor<Recipe>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<RecipeIngredient>()).isEmpty)
    }

    // MARK: - Helpers

    private func apply(_ draft: RecipeImportDraft, inventory: [Ingredient]? = nil) -> RecipeFormViewModel {
        let rows = RecipeIngredientReconciler.reconcile(draft, against: inventory ?? self.inventory)
        let model = RecipeFormViewModel()
        model.applyImport(PreparedRecipeImport(draft: draft, rows: rows))
        return model
    }

    private static func buildInventory(in context: ModelContext) -> [Ingredient] {
        let oils = IngredientCategory(name: IngredientCategory.Name.oils)
        let fragrances = IngredientCategory(name: IngredientCategory.Name.fragrances)
        context.insert(oils)
        context.insert(fragrances)

        func makeOil(_ name: String, sap: Double) -> Ingredient {
            let oil = Ingredient(name: name, category: oils, unit: "g")
            oil.sapValue = sap
            context.insert(oil)
            return oil
        }

        let lavender = Ingredient(name: "Lavender Essential Oil", category: fragrances, unit: "g")
        context.insert(lavender)
        return [
            makeOil("Olive Oil", sap: 0.1345),
            makeOil("Coconut Oil", sap: 0.1783),
            makeOil("Castor Oil", sap: 0.1286),
            lavender
        ]
    }
}
