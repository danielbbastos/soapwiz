import Testing
import Foundation
@testable import SoapWiz

@Suite("Recipe import evaluation comparison")
struct RecipeImportEvaluationComparisonTests {

    private func expected(_ json: String) throws -> ExpectedRecipe {
        try JSONDecoder().decode(ExpectedRecipe.self, from: Data(json.utf8))
    }

    private func result(_ field: String, _ results: [EvaluationFieldResult]) throws -> EvaluationFieldResult {
        try #require(results.first { $0.field == field })
    }

    // MARK: - Decoding

    @Test func decode_AbsentFields_AreNotScored() throws {
        let recipe = try expected(#"{"lyeType":"NaOH"}"#)
        let results = RecipeImportEvaluation.compare(recipe, with: RecipeImportDraft(lyeType: "NaOH"))
        #expect(results.map(\.field) == ["lyeType"])
    }

    @Test func decode_NullField_IsDistinctFromAbsent() throws {
        let recipe = try expected(#"{"superFat":null}"#)
        #expect(recipe.superFat == .null)
        #expect(recipe.waterParts == .absent)
    }

    @Test func decodeCases_BlankLinesAndBadJSON() throws {
        let good = #"{"id":"a","source":"s","origin":"real","input":"a.txt","expected":{}}"#
        let cases = try RecipeImportEvaluation.decodeCases(from: Data("\(good)\n\n".utf8))
        #expect(cases.count == 1)
        #expect(throws: RecipeImportEvaluationError.self) {
            try RecipeImportEvaluation.decodeCases(from: Data("{not json}".utf8))
        }
    }

    @Test func loadCases_TestBundle_FindsEveryCaseAndInput() throws {
        let bundle = Bundle(for: ComparisonBundleMarker.self)
        let cases = try RecipeImportEvaluation.loadCases(from: bundle)
        #expect(!cases.isEmpty)
        for evaluationCase in cases {
            let name = try #require(evaluationCase.input ?? evaluationCase.image)
            _ = try RecipeImportEvaluation.resourceURL(name, in: bundle)
        }
    }

    // MARK: - Null means empty

    @Test func compare_NullSuperFatWithValue_Fails() throws {
        let recipe = try expected(#"{"superFat":null}"#)
        var draft = RecipeImportDraft()
        draft.superFat = 5
        let field = try result("superFat", RecipeImportEvaluation.compare(recipe, with: draft))
        #expect(!field.passed)
    }

    @Test func compare_NullSuperFatWithNil_Passes() throws {
        let recipe = try expected(#"{"superFat":null}"#)
        let field = try result("superFat", RecipeImportEvaluation.compare(recipe, with: RecipeImportDraft()))
        #expect(field.passed)
    }

    @Test func compare_EmptyAdditivesWithRows_Fails() throws {
        let recipe = try expected(#"{"additives":[]}"#)
        var draft = RecipeImportDraft()
        draft.additives = [ImportedIngredient(name: "Salt", amount: 10, unit: "g")]
        let field = try result("additives", RecipeImportEvaluation.compare(recipe, with: draft))
        #expect(!field.passed)
    }

    // MARK: - Oils

    @Test func compare_WeightDraftOils_NormalisedToShares() throws {
        let recipe = try expected(#"{"oils":[{"name":"olive","percent":75},{"name":"coconut","percent":25}]}"#)
        var draft = RecipeImportDraft()
        draft.amountsArePercentages = false
        draft.oils = [
            ImportedIngredient(name: "Olive Oil", amount: 30, unit: "oz"),
            ImportedIngredient(name: "Coconut Oil", amount: 10, unit: "oz")
        ]
        let field = try result("oils", RecipeImportEvaluation.compare(recipe, with: draft))
        #expect(field.passed)
    }

    @Test func compare_OilShareOutsideTolerance_Fails() throws {
        let recipe = try expected(#"{"oils":[{"name":"olive","percent":50},{"name":"coconut","percent":50}]}"#)
        var draft = RecipeImportDraft()
        draft.oils = [
            ImportedIngredient(name: "Olive Oil", amount: 51, unit: nil),
            ImportedIngredient(name: "Coconut Oil", amount: 49, unit: nil)
        ]
        let field = try result("oils", RecipeImportEvaluation.compare(recipe, with: draft))
        #expect(!field.passed)
    }

    @Test func compare_ExtraOilRow_Fails() throws {
        let recipe = try expected(#"{"oils":[{"name":"olive","percent":100}]}"#)
        var draft = RecipeImportDraft()
        draft.oils = [
            ImportedIngredient(name: "Olive Oil", amount: 100, unit: nil),
            ImportedIngredient(name: "Mold", amount: 0, unit: nil)
        ]
        let field = try result("oils", RecipeImportEvaluation.compare(recipe, with: draft))
        #expect(!field.passed)
    }

    // MARK: - Batch

    @Test func compare_WeightDraftBatch_UsesSumOfOilsAndUnit() throws {
        let recipe = try expected(#"{"batchSize":40,"batchUnit":"oz"}"#)
        var draft = RecipeImportDraft()
        draft.amountsArePercentages = false
        draft.batchUnit = "oz"
        draft.oils = [
            ImportedIngredient(name: "Olive", amount: 25, unit: "oz"),
            ImportedIngredient(name: "Coconut", amount: 15, unit: "oz")
        ]
        let results = RecipeImportEvaluation.compare(recipe, with: draft)
        #expect(results.filter { !$0.passed }.isEmpty)
        #expect(results.count == 2)
    }

    // MARK: - Names

    @Test func nameMatches_IgnoresCaseAndDiacritics() {
        #expect(RecipeImportEvaluation.nameMatches(expected: "bergamota", draft: "Bergamóta Esencial"))
        #expect(RecipeImportEvaluation.nameMatches(expected: "sodium lactate", draft: "Lactate, Sodium"))
        #expect(RecipeImportEvaluation.nameMatches(expected: "olive", draft: "Olive Oil"))
    }

    @Test func nameMatches_MissingWord_IsFalse() {
        #expect(!RecipeImportEvaluation.nameMatches(expected: "sodium lactate", draft: "Sodium Hydroxide"))
        #expect(!RecipeImportEvaluation.nameMatches(expected: "", draft: "Olive"))
    }

    // MARK: - Units

    @Test func normalisedUnit_SynonymsCollapse() {
        for unit in ["oz", "Ounce", "ounces", "oz."] { #expect(RecipeImportEvaluation.normalisedUnit(unit) == "oz") }
        for unit in ["g", "gram", "Grams", "gr"] { #expect(RecipeImportEvaluation.normalisedUnit(unit) == "g") }
        for unit in ["tbsp", "Tablespoon", "tablespoons", "Tbsp."] { #expect(RecipeImportEvaluation.normalisedUnit(unit) == "tbsp") }
        for unit in ["tsp", "teaspoon", "teaspoons", "tsp."] { #expect(RecipeImportEvaluation.normalisedUnit(unit) == "tsp") }
        for unit in ["lb", "lbs", "pound", "pounds"] { #expect(RecipeImportEvaluation.normalisedUnit(unit) == "lb") }
    }

    @Test func compare_RowUnitSynonym_Matches() throws {
        let recipe = try expected(#"{"additives":[{"name":"clay","amount":4,"unit":"tablespoon"}]}"#)
        var draft = RecipeImportDraft()
        draft.additives = [ImportedIngredient(name: "Kaolin Clay", amount: 4, unit: "Tbsp.")]
        let field = try result("additives", RecipeImportEvaluation.compare(recipe, with: draft))
        #expect(field.passed)
    }

    @Test func compare_RowWithoutExpectedUnit_SkipsUnit() throws {
        let recipe = try expected(#"{"additives":[{"name":"salt","amount":2}]}"#)
        var draft = RecipeImportDraft()
        draft.additives = [ImportedIngredient(name: "Salt", amount: 2, unit: "oz")]
        let field = try result("additives", RecipeImportEvaluation.compare(recipe, with: draft))
        #expect(field.passed)
    }

    @Test func compare_RowWithoutExpectedAmount_MatchesOnNameOnly() throws {
        let recipe = try expected(#"{"additives":[{"name":"sugar"}]}"#)
        var draft = RecipeImportDraft()
        draft.additives = [ImportedIngredient(name: "Sugar", amount: 28, unit: "g")]
        let field = try result("additives", RecipeImportEvaluation.compare(recipe, with: draft))
        #expect(field.passed)
        #expect(field.expected == "sugar")
    }

    @Test func compare_RowWrongUnit_Fails() throws {
        let recipe = try expected(#"{"additives":[{"name":"salt","amount":2,"unit":"oz"}]}"#)
        var draft = RecipeImportDraft()
        draft.additives = [ImportedIngredient(name: "Salt", amount: 2, unit: "g")]
        let field = try result("additives", RecipeImportEvaluation.compare(recipe, with: draft))
        #expect(!field.passed)
    }

    // MARK: - Numbers

    @Test func numbersMatch_Tolerances() {
        #expect(RecipeImportEvaluation.numbersMatch(1000, 1009))
        #expect(!RecipeImportEvaluation.numbersMatch(1000, 1020))
        #expect(RecipeImportEvaluation.numbersMatch(0, 0.005))
        #expect(RecipeImportEvaluation.numbersMatch(2, 2.02, absolute: 0.02))
    }
}

private final class ComparisonBundleMarker {}
