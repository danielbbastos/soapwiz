import Testing
import Foundation
@testable import SoapWiz

/// Two bugs from the held-out evaluation: a three-column table whose ounce
/// column was read as thousands, and a litre of olive oil moved out of the oils.
@Suite("Recipe import stated weights and volume oils")
struct RecipeImportStatedWeightAndVolumeTests {

    // MARK: - Stated weights

    private static let threeColumns = """
        Base Ingredients Grams Ounces Percentage
        Coconut Oil 270 gr. 9.524 oz. 30%
        Palm Oil 270 gr. 9.524 oz. 30%
        Olive Oil 270 gr. 9.524 oz. 30%
        Shea Butter 90 gr. 3.175 oz. 10%
        """

    private static func draft(_ names: [String]) -> RecipeImportDraft {
        RecipeImportDraft.mock(
            oils: names.map { ImportedIngredient(name: $0, amount: 30, unit: "%") },
            batchSize: nil,
            batchUnit: nil
        )
    }

    @Test func statedPercentageRecipe_GrColumnBesideOunces_BatchIsTheGrams() throws {
        let draft = Self.draft(["Coconut Oil", "Palm Oil", "Olive Oil", "Shea Butter"])

        let recipe = try #require(RecipeImportDraftChecker.statedPercentageRecipe(draft, in: Self.threeColumns))

        #expect(recipe.amountsArePercentages)
        #expect(recipe.batchSize == 900)
        #expect(recipe.batchUnit == "g")
    }

    @Test func statedPercentageRecipe_OuncesOnly_ReadsTheDotAsDecimal() throws {
        let text = """
            Olive Oil 9.524 oz 40%
            Coconut Oil 14.286 oz 60%
            """
        let draft = Self.draft(["Olive Oil", "Coconut Oil"])

        let recipe = try #require(RecipeImportDraftChecker.statedPercentageRecipe(draft, in: text))

        #expect(abs(try #require(recipe.batchSize) - 23.81) < 0.001)
        #expect(recipe.batchUnit == "oz")
    }

    @Test func statedPercentageRecipe_PoundsWithDot_ReadsTheDotAsDecimal() throws {
        let text = """
            Olive Oil 1.500 lb 50%
            Coconut Oil 1.500 lb 50%
            """
        let draft = Self.draft(["Olive Oil", "Coconut Oil"])

        let recipe = try #require(RecipeImportDraftChecker.statedPercentageRecipe(draft, in: text))

        #expect(recipe.batchSize == 3)
        #expect(recipe.batchUnit == "lb")
    }

    @Test func statedPercentageRecipe_GramsWithThousandsDot_StillReadsAThousand() throws {
        let text = """
            Olive Oil 1.000 g 50%
            Coconut Oil 1.000 g 50%
            """
        let draft = Self.draft(["Olive Oil", "Coconut Oil"])

        let recipe = try #require(RecipeImportDraftChecker.statedPercentageRecipe(draft, in: text))

        #expect(recipe.batchSize == 2000)
        #expect(recipe.batchUnit == "g")
    }

    @Test(arguments: ["gram", "grams", "gr", "grs"])
    func statedPercentageRecipe_GramSpellings_AreGrams(spelling: String) throws {
        let text = """
            Olive Oil 100 \(spelling) 50%
            Coconut Oil 100 \(spelling) 50%
            """
        let draft = Self.draft(["Olive Oil", "Coconut Oil"])

        let recipe = try #require(RecipeImportDraftChecker.statedPercentageRecipe(draft, in: text))

        #expect(recipe.batchSize == 200)
        #expect(recipe.batchUnit == "g")
    }

    // MARK: - Oils measured by volume

    private func moved(_ name: String, unit: String, amount: Double = 1) -> RecipeImportDraft {
        let draft = RecipeImportDraft.mock(oils: [ImportedIngredient(name: name, amount: amount, unit: unit)])
        return RecipeImportDraftChecker.movingMisplacedRows(draft)
    }

    @Test func movingMisplacedRows_OliveOilInMillilitres_StaysAnOil() {
        let result = moved("Olive Oil", unit: "ml", amount: 1000)

        #expect(result.oils.map(\.name) == ["Olive Oil"])
        #expect(result.additives.isEmpty)
    }

    @Test func movingMisplacedRows_SpanishOilInLitres_StaysAnOil() {
        let result = moved("Aceite de oliva", unit: "L")

        #expect(result.oils.map(\.name) == ["Aceite de oliva"])
        #expect(result.additives.isEmpty)
    }

    @Test func movingMisplacedRows_GlycerinInSpoons_MovesToAdditives() {
        let result = moved("Glycerin", unit: "tbsp", amount: 2)

        #expect(result.oils.isEmpty)
        #expect(result.additives.map(\.name) == ["Glycerin"])
    }

    @Test func movingMisplacedRows_RoseWaterInMillilitres_MovesToAdditives() {
        let result = moved("Rose Water", unit: "ml", amount: 50)

        #expect(result.oils.isEmpty)
        #expect(result.additives.map(\.name) == ["Rose Water"])
    }

    // MARK: - Spanish oil wording

    @Test(arguments: ["Aceite de coco", "Aceites vegetales", "Manteca de karité", "Cera de abeja"])
    func evidentRole_SpanishOilWording_KeepsTheModelsSection(name: String) {
        #expect(ImportedIngredientName.hasOilWording(name))
        #expect(ImportedIngredientName.evidentRole(of: name) == nil)
    }

    @Test(arguments: ["Beeswax", "Beeswax pastilles", "Carnauba wax", "Carnauba", "Candelilla", "Candelilla wax"])
    func hasOilWording_Waxes_IsTrue(_ name: String) {
        #expect(ImportedIngredientName.hasOilWording(name))
    }

    @Test func hasOilWording_NoOilWord_IsFalse() {
        #expect(!ImportedIngredientName.hasOilWording("Rose Water"))
        #expect(!ImportedIngredientName.hasOilWording("Glycerin"))
    }
}
