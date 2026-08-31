import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The claim the whole issue rests on: export a recipe, import it, and get back
/// exactly what was exported.
///
/// Every test here goes the whole way round — `Recipe` → payload → `Recipe` —
/// rather than checking the encoder and the importer separately. A field can be
/// written and read consistently by both and still be wrong; only the round trip
/// catches that.
///
/// This suite covers the recipe itself: its settings, its rows, and travelling
/// in company. What becomes of the ingredients and collections it references is
/// `RecipeTransferResolutionTests`.
@MainActor
@Suite
struct RecipeTransferRoundTripTests {

    private let harness: RecipeTransferRoundTripHarness
    private var source: RecipeTransferFixture { harness.source }

    init() throws {
        harness = try RecipeTransferRoundTripHarness()
    }

    // MARK: - Every configuration field

    @Test func roundTrip_PopulatedRecipe_RestoresEveryConfigurationField() throws {
        let original = source.populatedRecipe()

        let imported = try #require(try harness.roundTrip([original]).first)

        #expect(imported.name == original.name)
        #expect(imported.desc == original.desc)
        #expect(imported.recipeKind == original.recipeKind)
        #expect(imported.weightUnit == original.weightUnit)
        #expect(imported.totalOilWeight == original.totalOilWeight)
        #expect(imported.oilWeightUnit == original.oilWeightUnit)
        #expect(imported.lyeType == original.lyeType)
        #expect(imported.lyePurity == original.lyePurity)
        #expect(imported.waterParts == original.waterParts)
        #expect(imported.superFat == original.superFat)
        #expect(imported.fragrancePercentage == original.fragrancePercentage)
        #expect(imported.fragranceUnit == original.fragranceUnit)
    }

    /// The four configurations `RecipeImportDraft` cannot express, which is why
    /// the exact path had to exist at all.
    @Test func roundTrip_HybridLyeRecipe_RestoresTheSplitAndBothPurities() throws {
        let original = source.recipe(named: "Hybrid Bar")
        original.useHybrid = true
        original.kohPercentage = 73
        original.naohPercentage = 27
        original.kohPurity = 88.5
        original.naohPurity = 97.25
        source.addOil(source.oil("Olive Oil"), percentage: 100, to: original)

        let imported = try #require(try harness.roundTrip([original]).first)

        #expect(imported.useHybrid)
        #expect(imported.kohPercentage == 73)
        #expect(imported.naohPercentage == 27)
        #expect(imported.kohPurity == 88.5)
        #expect(imported.naohPurity == 97.25)
    }

    @Test func roundTrip_CreamSoapRecipe_RestoresTheMethod() throws {
        let original = source.recipe(named: "Cream Soap")
        original.isCreamSoap = true
        original.useCFM = false
        source.addOil(source.oil("Stearic Acid"), percentage: 100, to: original)

        let imported = try #require(try harness.roundTrip([original]).first)

        #expect(imported.isCreamSoap)
        #expect(!imported.useCFM)
    }

    @Test func roundTrip_CFMRecipe_RestoresTheNeutralizer() throws {
        let original = source.recipe(named: "Liquid Soap")
        original.useCFM = true
        original.cfmNeutralizer = CFMNeutralizer.borax.rawValue
        source.addOil(source.oil("Coconut Oil"), percentage: 100, to: original)

        let imported = try #require(try harness.roundTrip([original]).first)

        #expect(imported.useCFM)
        #expect(imported.cfmNeutralizer == CFMNeutralizer.borax.rawValue)
    }

    @Test func roundTrip_NonSoapRecipe_RestoresItsKind() throws {
        let original = source.recipe(named: "Beeswax Candle")
        original.recipeKind = RecipeKind.general.rawValue
        source.addOil(source.oil("Beeswax"), percentage: 100, to: original)

        let imported = try #require(try harness.roundTrip([original]).first)

        #expect(RecipeKind.resolve(imported.recipeKind) == .general)
    }

    // MARK: - Line items and products

    @Test func roundTrip_LineItems_RestoreRolesAmountsAndUnits() throws {
        let original = source.populatedRecipe()

        let imported = try #require(try harness.roundTrip([original]).first)

        let oils = imported.ingredients.filter { $0.ingredientRole == .oil }
        #expect(oils.count == 3)
        #expect(oils.map(\.percentage).reduce(0, +) == 100)
        #expect(Set(oils.compactMap { $0.ingredient?.name }) == ["Olive Oil", "Coconut Oil", "Castor Oil"])

        let additive = try #require(imported.ingredients.first { $0.ingredientRole == .additive })
        #expect(additive.ingredient?.name == "Sodium Lactate")
        #expect(additive.additiveAmount == 2.5)
        #expect(additive.additiveUnit == "% of oils")

        let fragrance = try #require(imported.ingredients.first { $0.ingredientRole == .fragrance })
        #expect(fragrance.additiveAmount == 60)
        #expect(fragrance.additiveUnit == FragranceUnit.percentOfFragrances.rawValue)
    }

    @Test func roundTrip_Products_RestoreSizeAndUnit() throws {
        let original = source.populatedRecipe()

        let imported = try #require(try harness.roundTrip([original]).first)

        #expect(imported.products.count == 2)
        #expect(imported.products.contains { $0.size == 100 && $0.unitSymbol == "g" })
        #expect(imported.products.contains { $0.unitSymbol == ProductUnit.partsOfBatch.rawValue })
    }

    /// The lye weight the recipient calculates has to be the one the sender saw.
    /// Every field above exists to make this true; this asserts the result
    /// rather than the inputs.
    @Test func roundTrip_PopulatedRecipe_CalculatesTheSameLyeWeight() throws {
        let original = source.populatedRecipe()
        let imported = try #require(try harness.roundTrip([original]).first)

        let before = RecipeFormViewModel()
        before.load(from: original)
        let after = RecipeFormViewModel()
        after.load(from: imported)

        #expect(after.calculatedLyeAmount == before.calculatedLyeAmount)
        #expect(after.calculatedWaterAmount == before.calculatedWaterAmount)
    }

    // MARK: - Many recipes

    @Test func roundTrip_FifteenRecipes_AllComeBackMatchingTheirOriginals() throws {
        let originals = (1...15).map { index -> Recipe in
            let recipe = source.recipe(named: "Bar \(index)")
            recipe.totalOilWeight = Double(index) * 100
            source.addOil(source.oil("Olive Oil"), percentage: 60, to: recipe)
            source.addOil(source.oil("Coconut Oil \(index)"), percentage: 40, to: recipe)
            return recipe
        }

        let imported = try harness.roundTrip(originals)

        #expect(imported.count == 15)
        for (original, restored) in zip(originals, imported) {
            #expect(restored.name == original.name)
            #expect(restored.totalOilWeight == original.totalOilWeight)
            #expect(restored.ingredients.count == 2)
        }
    }

    /// Fifteen recipes sharing an oil must not produce fifteen copies of it.
    @Test func roundTrip_RecipesSharingAnOil_CreateItOnce() throws {
        let shared = source.oil("Olive Oil")
        let recipes = (1...5).map { index -> Recipe in
            let recipe = source.recipe(named: "Bar \(index)")
            source.addOil(shared, percentage: 100, to: recipe)
            return recipe
        }

        try harness.roundTrip(recipes)

        let olives = try harness.received(Ingredient.self)
            .filter { $0.name == "Olive Oil" }
        #expect(olives.count == 1)
    }

    // MARK: - Clipboard transport

    /// The same round trip, over the other transport.
    @Test func clipboardRoundTrip_PopulatedRecipe_RestoresTheSameRecipe() throws {
        let original = source.populatedRecipe()
        source.context.processPendingChanges()

        let clipboard = RecipeTextExporter.clipboardText(for: original)
        guard case .payload(let payload) = RecipeTransferMarker.scan(clipboard) else {
            Issue.record("Expected the clipboard text to carry a payload")
            return
        }
        let imported = try #require(try harness.importIntoDestination(payload).first)

        #expect(imported.name == original.name)
        #expect(imported.useHybrid == original.useHybrid)
        #expect(imported.isCreamSoap == original.isCreamSoap)
        #expect(imported.useCFM == original.useCFM)
        #expect(imported.ingredients.count == original.ingredients.count)
        #expect(imported.products.count == original.products.count)
    }
}
