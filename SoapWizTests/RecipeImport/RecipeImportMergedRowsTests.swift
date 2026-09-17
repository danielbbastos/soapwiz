import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// What happens when two import rows resolve to one ingredient.
///
/// Catalog aliases made this ordinary: "Olive Oil" and "Sweet Oil" are two names
/// for one oil, so a recipe naming both is asking for the sum. A line read twice
/// under the *same* name is the opposite — one entry seen twice — and must not be
/// doubled. The written name is what separates them.
@Suite("Recipe import — rows resolving to one ingredient", .serialized)
@MainActor
struct RecipeImportMergedRowsTests: RecipeImportTestHelpers {

    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        let schema = Schema([
            Recipe.self, RecipeIngredient.self, RecipeProduct.self,
            Ingredient.self, IngredientPurchase.self, IngredientCategory.self
        ])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        context = container.mainContext
    }

    // MARK: - Oils

    /// The case found on device: "Sweet Oil" is a catalog alias of olive oil, so
    /// both lines resolve to one row. 45% + 10% is 55% of that oil, and dropping
    /// either loses a quantity the recipe stated.
    @Test func applyImport_TwoNamesForOneOil_AddsTheAmounts() throws {
        let inventory = makeOliveAndCoconut()
        let draft = RecipeImportDraft.mock(oils: [
            ImportedIngredient(name: "Olive Oil", amount: 45, unit: nil),
            ImportedIngredient(name: "Coconut Oil", amount: 45, unit: nil),
            ImportedIngredient(name: "Sweet Oil", amount: 10, unit: nil)
        ])

        let model = apply(draft, inventory: inventory)

        #expect(model.oilDrafts.count == 2)
        let olive = try #require(model.oilDrafts.first { $0.ingredient.name == "Olive Oil" })
        #expect(olive.amount == 55)
    }

    @Test func applyImport_TwoNamesForOneOil_SaysSoInTheDescription() throws {
        let inventory = makeOliveAndCoconut()
        let draft = RecipeImportDraft.mock(oils: [
            ImportedIngredient(name: "Olive Oil", amount: 45, unit: nil),
            ImportedIngredient(name: "Sweet Oil", amount: 10, unit: nil)
        ])

        let model = apply(draft, inventory: inventory)

        #expect(model.desc.contains("Named more than once and added together"))
        // Both names the source used, not just the ingredient's own: naming only
        // "Olive Oil" leaves no way to tell which other line went into it.
        #expect(model.desc.contains("Olive Oil"))
        #expect(model.desc.contains("Sweet Oil"))
    }

    /// The behaviour the merging must not break: one line read twice — a sticky
    /// table header and the body — is a single entry, and summing it would double
    /// the recipe.
    @Test func applyImport_SameNameTwice_KeepsOneAmount() throws {
        let inventory = makeOliveAndCoconut()
        let draft = RecipeImportDraft.mock(oils: [
            ImportedIngredient(name: "Olive Oil", amount: 55, unit: nil),
            ImportedIngredient(name: "Olive Oil", amount: 55, unit: nil)
        ])

        let model = apply(draft, inventory: inventory)

        let olive = try #require(model.oilDrafts.first { $0.ingredient.name == "Olive Oil" })
        #expect(olive.amount == 55)
        #expect(model.desc.contains("Repeated in the source, kept once"))
    }

    /// Three names for one oil: all three are listed, so every folded line is
    /// accounted for.
    @Test func applyImport_ThreeNamesForOneOil_ListsEveryName() throws {
        let inventory = makeOliveAndCoconut()
        let draft = RecipeImportDraft.mock(oils: [
            ImportedIngredient(name: "Olive Oil", amount: 40, unit: nil),
            ImportedIngredient(name: "Sweet Oil", amount: 10, unit: nil),
            ImportedIngredient(name: "Olive Oil - All Grades", amount: 10, unit: nil)
        ])

        let model = apply(draft, inventory: inventory)

        let olive = try #require(model.oilDrafts.first { $0.ingredient.name == "Olive Oil" })
        #expect(olive.amount == 60)
        #expect(model.desc.contains("Sweet Oil"))
        #expect(model.desc.contains("Olive Oil - All Grades"))
    }

    // MARK: - Additives

    @Test func applyImport_TwoNamesForOneAdditive_SameUnit_AddsTheAmounts() throws {
        let inventory = makeTableSalt()
        let draft = RecipeImportDraft.mock(
            oils: [ImportedIngredient(name: "Olive Oil", amount: 100, unit: nil)],
            additives: [
                ImportedIngredient(name: "Table Salt", amount: 10, unit: "g"),
                ImportedIngredient(name: "Sodium Chloride", amount: 5, unit: "g")
            ]
        )

        let model = apply(draft, inventory: inventory)

        #expect(model.additiveDrafts.count == 1)
        #expect(model.additiveDrafts.first?.amount == 15)
    }

    /// "10 g" and "2% of oils" describe different quantities. Adding the numbers
    /// would invent a third that is neither, so the first amount stands.
    @Test func applyImport_TwoNamesForOneAdditive_DifferentUnits_DoesNotAdd() throws {
        let inventory = makeTableSalt()
        let draft = RecipeImportDraft.mock(
            oils: [ImportedIngredient(name: "Olive Oil", amount: 100, unit: nil)],
            additives: [
                ImportedIngredient(name: "Table Salt", amount: 10, unit: "g"),
                ImportedIngredient(name: "Sodium Chloride", amount: 2, unit: "% of oils")
            ]
        )

        let model = apply(draft, inventory: inventory)

        #expect(model.additiveDrafts.count == 1)
        #expect(model.additiveDrafts.first?.amount == 10)
        #expect(model.desc.contains("Repeated in the source, kept once"))
    }

    // MARK: - Helpers

    private func apply(_ draft: RecipeImportDraft, inventory: [Ingredient]) -> RecipeFormViewModel {
        let rows = RecipeIngredientReconciler.reconcile(draft, against: inventory)
        let model = RecipeFormViewModel()
        model.applyImport(PreparedRecipeImport(draft: draft, rows: rows))
        return model
    }

    /// Olive oil carrying its catalog slug, so "Sweet Oil" can reach it through the
    /// alias lookup, plus a second oil so the recipe has something else in it.
    private func makeOliveAndCoconut() -> [Ingredient] {
        let oils = IngredientCategory(name: IngredientCategory.Name.oils)
        context.insert(oils)
        let olive = makeOil(name: "Olive Oil", sap: 0.1345, category: oils, context: context)
        olive.librarySlug = "olive-oil"
        let coconut = makeOil(name: "Coconut Oil", sap: 0.1783, category: oils, context: context)
        coconut.librarySlug = "coconut-oil"
        return [olive, coconut]
    }

    /// Table salt, whose catalog entry carries "Sodium Chloride" as an alias — two
    /// names for one additive with no textual resemblance, the same shape as the
    /// Olive Oil / Sweet Oil case. Plus an oil, so the recipe is valid.
    private func makeTableSalt() -> [Ingredient] {
        let oils = IngredientCategory(name: IngredientCategory.Name.oils)
        let additives = IngredientCategory(name: IngredientCategory.Name.additives)
        context.insert(oils)
        context.insert(additives)
        let olive = makeOil(name: "Olive Oil", sap: 0.1345, category: oils, context: context)
        olive.librarySlug = "olive-oil"
        let salt = Ingredient(name: "Table Salt", category: additives, unit: "g")
        salt.librarySlug = "table-salt"
        context.insert(salt)
        return [olive, salt]
    }
}
