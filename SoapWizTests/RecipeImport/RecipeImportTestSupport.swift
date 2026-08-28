import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Shared helpers for the recipe-import suites.
@MainActor
protocol RecipeImportTestHelpers {}

extension RecipeImportTestHelpers {
    func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            Recipe.self, RecipeIngredient.self, RecipeProduct.self,
            Ingredient.self, IngredientPurchase.self, IngredientCategory.self
        ])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    /// Olive, coconut and castor with SAP values, plus a lavender fragrance —
    /// enough inventory for an import to resolve against.
    func makeInventory(in context: ModelContext) -> [Ingredient] {
        let oils = IngredientCategory(name: IngredientCategory.Name.oils)
        let fragrances = IngredientCategory(name: IngredientCategory.Name.fragrances)
        context.insert(oils)
        context.insert(fragrances)

        let inventory = [
            makeOil(name: "Olive Oil", sap: 0.1345, category: oils, context: context),
            makeOil(name: "Coconut Oil", sap: 0.1783, category: oils, context: context),
            makeOil(name: "Castor Oil", sap: 0.1286, category: oils, context: context)
        ]
        let lavender = Ingredient(name: "Lavender Essential Oil", category: fragrances, unit: "g")
        context.insert(lavender)
        return inventory + [lavender]
    }

    func makeOil(name: String, sap: Double, category: IngredientCategory?, context: ModelContext) -> Ingredient {
        let oil = Ingredient(name: name, category: category, unit: "g")
        oil.sapValue = sap
        context.insert(oil)
        return oil
    }
}

/// Returns a canned draft, or throws a canned error, without going anywhere
/// near Apple Intelligence — which is unavailable in the simulator.
struct StubRecipeExtractor: RecipeDraftExtracting {
    var result: Result<RecipeImportDraft, RecipeImportError>

    /// The text the last call was given, so a test can assert what the
    /// sanitizer handed over.
    final class Recorder: @unchecked Sendable {
        var lastText: SanitizedRecipeText?
    }
    let recorder = Recorder()

    init(draft: RecipeImportDraft) {
        result = .success(draft)
    }

    init(error: RecipeImportError) {
        result = .failure(error)
    }

    func extract(from text: SanitizedRecipeText) async throws -> RecipeImportDraft {
        recorder.lastText = text
        return try result.get()
    }
}

/// Fails the first call with `firstError`, then succeeds. Covers the retry the
/// view model performs when the model says the input didn't fit.
final class RetryingStubExtractor: RecipeDraftExtracting, @unchecked Sendable {
    private let firstError: RecipeImportError
    private let draft: RecipeImportDraft
    private(set) var callCount = 0
    private(set) var budgets: [Int] = []

    init(firstError: RecipeImportError, then draft: RecipeImportDraft) {
        self.firstError = firstError
        self.draft = draft
    }

    func extract(from text: SanitizedRecipeText) async throws -> RecipeImportDraft {
        callCount += 1
        budgets.append(text.text.count)
        if callCount == 1 { throw firstError }
        return draft
    }
}

extension RecipeImportDraft {
    static func mock(
        name: String = "Castile Bar",
        oils: [ImportedIngredient] = [
            ImportedIngredient(name: "Olive Oil", amount: 70, unit: nil),
            ImportedIngredient(name: "Coconut Oil", amount: 30, unit: nil)
        ],
        additives: [ImportedIngredient] = [],
        fragrances: [ImportedIngredient] = [],
        amountsArePercentages: Bool = true,
        batchSize: Double? = 1000,
        batchUnit: String? = "g",
        lyeType: String? = "NaOH",
        superFat: Double? = 5,
        waterParts: Double? = 2,
        fragrancePercentage: Double? = 3
    ) -> RecipeImportDraft {
        RecipeImportDraft(
            name: name,
            oils: oils,
            additives: additives,
            fragrances: fragrances,
            amountsArePercentages: amountsArePercentages,
            batchSize: batchSize,
            batchUnit: batchUnit,
            lyeType: lyeType,
            superFat: superFat,
            waterParts: waterParts,
            fragrancePercentage: fragrancePercentage
        )
    }
}
