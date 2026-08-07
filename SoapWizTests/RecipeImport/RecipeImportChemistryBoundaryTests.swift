import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The safety criterion, enforced structurally rather than by review.
///
/// A saponification value the model invented would produce a wrong lye weight,
/// and lye-heavy soap burns. These tests fail the moment anyone adds a field
/// that could carry chemistry into a recipe without a human entering it.
@Suite("Recipe import chemistry boundary", .serialized)
@MainActor
struct RecipeImportChemistryBoundaryTests: RecipeImportTestHelpers {

    /// Substrings that name something feeding `LyeCalculator`.
    private static let forbidden = ["sap", "density", "fattyacid", "saponif", "lyeamount", "waterweight"]

    @Test func draft_ExposesNoChemistryField() {
        let labels = Self.labels(of: RecipeImportDraft.mock())
        #expect(!labels.isEmpty)
        for label in labels {
            #expect(!Self.namesChemistry(label), "RecipeImportDraft must not expose '\(label)'")
        }
    }

    @Test func importedIngredient_ExposesOnlyNameAmountAndUnit() {
        let labels = Self.labels(of: ImportedIngredient(name: "Olive Oil", amount: 70, unit: "%"))
        #expect(Set(labels) == ["id", "name", "amount", "unit"])
    }

    @Test func preparedImport_ExposesNoChemistryField() {
        let prepared = PreparedRecipeImport(draft: .mock(), rows: [])
        for label in Self.labels(of: prepared) {
            #expect(!Self.namesChemistry(label), "PreparedRecipeImport must not expose '\(label)'")
        }
    }

    @available(iOS 26, macOS 26, *)
    @Test func generatedDraft_TheSchemaTheModelFills_ExposesNoChemistryField() {
        let generated = GeneratedRecipeDraft(
            name: "Castile",
            oils: [GeneratedIngredient(name: "Olive Oil", amount: 100, unit: "%")],
            additives: [],
            fragrances: [],
            amountsArePercentages: true,
            batchSize: 1_000,
            batchUnit: "g",
            lyeType: "NaOH",
            superFat: 5,
            waterParts: 2,
            fragrancePercentage: 3
        )
        let labels = Self.labels(of: generated)
        #expect(!labels.isEmpty)
        for label in labels {
            #expect(!Self.namesChemistry(label), "GeneratedRecipeDraft must not expose '\(label)'")
        }
    }

    /// An imported recipe inherits its chemistry from the inventory ingredient
    /// it matched, and from nowhere else.
    @Test func importedRecipe_TakesItsSapValueFromInventory() throws {
        let (container, context) = try makeContext()
        _ = container
        let inventory = makeInventory(in: context)
        let olive = try #require(inventory.first { $0.name == "Olive Oil" })

        let draft = RecipeImportDraft.mock(oils: [ImportedIngredient(name: "Olive Oil", amount: 100, unit: nil)])
        let rows = RecipeIngredientReconciler.reconcile(draft, against: inventory)
        let model = RecipeFormViewModel()
        model.applyImport(PreparedRecipeImport(draft: draft, rows: rows))

        #expect(model.oilDrafts.first?.ingredient.sapValue == olive.sapValue)
        #expect(model.oilDrafts.first?.ingredient === olive)
    }

    /// An oil with no SAP value in the inventory stays without one. The import
    /// must not fill the gap.
    @Test func importedRecipe_IngredientWithoutSap_GainsNoSapValue() throws {
        let (container, context) = try makeContext()
        _ = container
        let oil = Ingredient(name: "Mystery Oil", unit: "g")
        context.insert(oil)

        let draft = RecipeImportDraft.mock(oils: [ImportedIngredient(name: "Mystery Oil", amount: 100, unit: nil)])
        let rows = RecipeIngredientReconciler.reconcile(draft, against: [oil])
        let model = RecipeFormViewModel()
        model.applyImport(PreparedRecipeImport(draft: draft, rows: rows))

        #expect(model.oilDrafts.first?.ingredient.sapValue == nil)
        #expect(model.oilDrafts.first?.ingredient.density == nil)
        #expect(model.oilDrafts.first?.ingredient.fattyAcidProfile == nil)
    }

    // MARK: - Reflection helpers

    /// Property labels of `value`, following one level into its collections so
    /// a nested ingredient type is checked too.
    private static func labels(of value: Any) -> [String] {
        var found: [String] = []
        for child in Mirror(reflecting: value).children {
            if let label = child.label { found.append(label) }
            let mirror = Mirror(reflecting: child.value)
            if mirror.displayStyle == .collection {
                found.append(contentsOf: mirror.children.flatMap { labels(of: $0.value) })
            } else if mirror.displayStyle == .struct {
                found.append(contentsOf: mirror.children.compactMap(\.label))
            }
        }
        return found
    }

    private static func namesChemistry(_ label: String) -> Bool {
        let normalised = label.lowercased().replacingOccurrences(of: "_", with: "")
        return forbidden.contains { normalised.contains($0) }
    }
}
