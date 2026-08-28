import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// What the text path does with a recipe that isn't soap, or that says nothing
/// about saponifying.
///
/// The extraction schema has no notion of a recipe kind, so the only honest
/// signal is what the source actually stated. These cover the two places that
/// used to assume soap regardless.
@Suite("Recipe import → non-soap", .serialized)
@MainActor
struct RecipeImportNonSoapTests {

    private let container: ModelContainer
    private let context: ModelContext
    private let inventory: [Ingredient]

    init() throws {
        let schema = Schema([
            Recipe.self, RecipeIngredient.self, RecipeProduct.self,
            Ingredient.self, IngredientPurchase.self, IngredientCategory.self
        ])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        let context = container.mainContext
        self.container = container
        self.context = context
        inventory = Self.buildInventory(in: context)
    }

    /// Olive, coconut and castor with SAP values, plus a lavender fragrance.
    /// Static so it can run before `self` is fully initialised.
    private static func buildInventory(in context: ModelContext) -> [Ingredient] {
        let oils = IngredientCategory(name: IngredientCategory.Name.oils)
        let fragrances = IngredientCategory(name: IngredientCategory.Name.fragrances)
        context.insert(oils)
        context.insert(fragrances)

        func oil(_ name: String, sap: Double) -> Ingredient {
            let ingredient = Ingredient(name: name, category: oils, unit: "g")
            ingredient.sapValue = sap
            context.insert(ingredient)
            return ingredient
        }

        let lavender = Ingredient(name: "Lavender Essential Oil", category: fragrances, unit: "g")
        context.insert(lavender)
        return [
            oil("Olive Oil", sap: 0.1345),
            oil("Coconut Oil", sap: 0.1783),
            oil("Castor Oil", sap: 0.1286),
            lavender
        ]
    }

    // MARK: - Lye settings the source never stated

    @Test func statesLyeSettings_NothingStated_IsFalse() {
        let draft = RecipeImportDraft.mock(lyeType: nil, superFat: nil, waterParts: nil)

        #expect(!draft.statesLyeSettings)
    }

    @Test func statesLyeSettings_OnlySuperFatStated_IsTrue() {
        #expect(RecipeImportDraft.mock(lyeType: nil, superFat: 5, waterParts: nil).statesLyeSettings)
    }

    @Test func statesLyeSettings_OnlyLyeStated_IsTrue() {
        #expect(RecipeImportDraft.mock(lyeType: "KOH", superFat: nil, waterParts: nil).statesLyeSettings)
    }

    /// A source that names no lye leaves the form on its own default rather
    /// than being told the recipe wants NaOH.
    @Test func applyImport_NoLyeStated_KeepsTheFormsDefault() {
        let model = apply(.mock(lyeType: nil, superFat: nil, waterParts: nil))

        #expect(model.lyeType == "NaOH")
        #expect(model.superFat == 5)
        #expect(model.waterParts == 1.5)
    }

    @Test func applyImport_LyeStated_StillAdoptsIt() {
        let model = apply(.mock(lyeType: "KOH"))

        #expect(model.lyeType == "KOH")
    }

    // MARK: - Fragrance units on a general recipe (SW-121)

    /// `% of batch` resolves against the lye and the water, which a general
    /// recipe has none of. Adopting it doesn't merely read oddly: the row
    /// resolves to nothing, drops out of the cost breakdown, and is never
    /// deducted at batch creation.
    @Test func applyImport_GeneralRecipeWithPercentOfBatchFragrance_DoesNotAdoptThatUnit() {
        let draft = RecipeImportDraft.mock(
            fragrances: [ImportedIngredient(name: "Lavender Essential Oil", amount: 3, unit: "% of batch")]
        )

        let model = generalFormApplying(draft)

        #expect(model.fragranceUnit != .percentOfBatch)
        #expect(model.availableFragranceUnits.contains(model.fragranceUnit))
    }

    @Test func applyImport_GeneralRecipeWithPercentOfLiquidsFragrance_DoesNotAdoptThatUnit() {
        let draft = RecipeImportDraft.mock(
            fragrances: [ImportedIngredient(name: "Lavender Essential Oil", amount: 3, unit: "% of liquids")]
        )

        let model = generalFormApplying(draft)

        #expect(model.fragranceUnit != .percentOfLiquids)
        #expect(model.availableFragranceUnits.contains(model.fragranceUnit))
    }

    /// The fragrance still has to reach the cost breakdown, which is the
    /// consequence the unit choice was threatening.
    @Test func applyImport_GeneralRecipeFragrance_IsStillCosted() throws {
        let draft = RecipeImportDraft.mock(
            fragrances: [ImportedIngredient(name: "Lavender Essential Oil", amount: 3, unit: "% of batch")]
        )

        let model = generalFormApplying(draft)

        #expect(model.fragranceDrafts.count == 1)
        let costed = model.wholeBatchBreakdown.fragrances
        #expect(costed.count == 1)
        #expect(try #require(costed.first).ingredientAmount > 0)
    }

    /// A soap recipe is unaffected: every unit remains available to it.
    @Test func applyImport_SoapRecipeWithPercentOfBatchFragrance_StillAdoptsIt() {
        let draft = RecipeImportDraft.mock(
            fragrances: [ImportedIngredient(name: "Lavender Essential Oil", amount: 3, unit: "% of batch")]
        )

        let model = apply(draft)

        #expect(model.fragranceUnit == .percentOfBatch)
    }

    // MARK: - Helpers

    private func apply(_ draft: RecipeImportDraft) -> RecipeFormViewModel {
        let model = RecipeFormViewModel()
        model.applyImport(prepared(draft))
        return model
    }

    /// A form already set to a non-soap kind before the import lands, which is
    /// the state the fragrance-unit guard exists for.
    private func generalFormApplying(_ draft: RecipeImportDraft) -> RecipeFormViewModel {
        let model = RecipeFormViewModel()
        model.recipeKind = .general
        model.applyImport(prepared(draft))
        return model
    }

    private func prepared(_ draft: RecipeImportDraft) -> PreparedRecipeImport {
        PreparedRecipeImport(draft: draft, rows: RecipeIngredientReconciler.reconcile(draft, against: inventory))
    }
}
