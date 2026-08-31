import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// What the encoder puts in a payload, and what it deliberately leaves out.
@MainActor
@Suite
struct RecipeTransferEncoderTests {

    private let fixture: RecipeTransferFixture

    init() throws {
        fixture = try RecipeTransferFixture()
    }

    // MARK: - Configuration fields

    @Test func payload_PopulatedRecipe_CarriesEveryConfigurationField() throws {
        let recipe = fixture.populatedRecipe()

        let encoded = try #require(RecipeTransferEncoder.payload(for: [recipe]).recipes.first)

        #expect(encoded.name == recipe.name)
        #expect(encoded.desc == recipe.desc)
        #expect(encoded.recipeKind == recipe.recipeKind)
        #expect(encoded.weightUnit == recipe.weightUnit)
        #expect(encoded.totalOilWeight == recipe.totalOilWeight)
        #expect(encoded.oilWeightUnit == recipe.oilWeightUnit)
        #expect(encoded.lyeType == recipe.lyeType)
        #expect(encoded.lyePurity == recipe.lyePurity)
        #expect(encoded.waterParts == recipe.waterParts)
        #expect(encoded.superFat == recipe.superFat)
        #expect(encoded.fragrancePercentage == recipe.fragrancePercentage)
        #expect(encoded.fragranceUnit == recipe.fragranceUnit)
    }

    /// The configurations `RecipeImportDraft` cannot express, which are the
    /// whole reason this format exists.
    @Test func payload_HybridCreamAndCFMRecipe_CarriesTheSettingsTheDraftCannot() throws {
        let recipe = fixture.populatedRecipe()

        let encoded = try #require(RecipeTransferEncoder.payload(for: [recipe]).recipes.first)

        #expect(encoded.useHybrid)
        #expect(encoded.kohPercentage == 73)
        #expect(encoded.naohPercentage == 27)
        #expect(encoded.kohPurity == 88.5)
        #expect(encoded.naohPurity == 97.25)
        #expect(encoded.isCreamSoap)
        #expect(encoded.useCFM)
        #expect(encoded.cfmNeutralizer == CFMNeutralizer.borax.rawValue)
    }

    @Test func payload_NonSoapRecipe_CarriesItsKind() throws {
        let recipe = fixture.recipe(named: "Beeswax Candle")
        recipe.recipeKind = RecipeKind.general.rawValue
        fixture.addOil(fixture.oil("Beeswax"), percentage: 100, to: recipe)

        let encoded = try #require(RecipeTransferEncoder.payload(for: [recipe]).recipes.first)

        #expect(encoded.recipeKind == RecipeKind.general.rawValue)
        #expect(encoded.kind == .general)
    }

    // MARK: - Line items

    @Test func payload_LineItems_KeepRoleAmountAndUnit() throws {
        let recipe = fixture.populatedRecipe()
        let payload = RecipeTransferEncoder.payload(for: [recipe])
        let encoded = try #require(payload.recipes.first)

        let oils = encoded.ingredients.filter { $0.role == RecipeIngredientRole.oil.rawValue }
        #expect(oils.count == 3)
        #expect(oils.map(\.percentage).reduce(0, +) == 100)

        let additive = try #require(
            encoded.ingredients.first { $0.role == RecipeIngredientRole.additive.rawValue }
        )
        #expect(additive.additiveAmount == 2.5)
        #expect(additive.additiveUnit == "% of oils")
        #expect(payload.ingredients[additive.ingredientIndex].name == "Sodium Lactate")

        let fragrance = try #require(
            encoded.ingredients.first { $0.role == RecipeIngredientRole.fragrance.rawValue }
        )
        #expect(fragrance.additiveAmount == 60)
        #expect(fragrance.additiveUnit == FragranceUnit.percentOfFragrances.rawValue)
    }

    @Test func payload_UnresolvedLineItem_IsDropped() throws {
        let recipe = fixture.recipe()
        fixture.addOil(fixture.oil("Olive Oil"), percentage: 100, to: recipe)
        let orphan = RecipeIngredient(ingredient: nil, percentage: 50, role: .oil)
        orphan.recipe = recipe
        fixture.context.insert(orphan)
        fixture.context.processPendingChanges()

        let encoded = try #require(RecipeTransferEncoder.payload(for: [recipe]).recipes.first)

        #expect(encoded.ingredients.count == 1)
    }

    @Test func payload_Products_KeepSizeAndUnit() throws {
        let recipe = fixture.populatedRecipe()

        let encoded = try #require(RecipeTransferEncoder.payload(for: [recipe]).recipes.first)

        #expect(encoded.products.count == 2)
        #expect(encoded.products.contains { $0.size == 100 && $0.unitSymbol == "g" })
        #expect(encoded.products.contains { $0.unitSymbol == ProductUnit.partsOfBatch.rawValue })
    }

    // MARK: - Ingredient chemistry

    @Test func payload_Ingredients_CarryChemistryTheRecipientCannotEnterByHand() throws {
        let recipe = fixture.recipe()
        fixture.addOil(fixture.oil("Olive Oil", sap: 0.1345, kohSap: 0.1885, density: 0.911), percentage: 100, to: recipe)

        let payload = RecipeTransferEncoder.payload(for: [recipe])
        let encoded = try #require(payload.ingredients.first)

        #expect(encoded.name == "Olive Oil")
        #expect(encoded.unit == "g")
        #expect(encoded.sapValue == 0.1345)
        #expect(encoded.kohSapValue == 0.1885)
        #expect(encoded.density == 0.911)
        #expect(encoded.fattyAcidProfile == .mock)
    }

    @Test func payload_IngredientWithoutChemistry_CarriesNilRatherThanZero() throws {
        let recipe = fixture.recipe()
        fixture.addAmountRow(
            fixture.oil("Mica", sap: nil, kohSap: nil, density: nil, profile: nil),
            role: .additive,
            amount: 1,
            unit: "g",
            to: recipe
        )

        let encoded = try #require(RecipeTransferEncoder.payload(for: [recipe]).ingredients.first)

        // Zero is a claim about chemistry; absent is the absence of one. An oil
        // whose SAP value arrived as 0 would calculate no lye at all.
        #expect(encoded.sapValue == nil)
        #expect(encoded.kohSapValue == nil)
        #expect(encoded.density == nil)
        #expect(encoded.fattyAcidProfile == nil)
    }

    // MARK: - Collections

    @Test func payload_Collections_CarryNamesOnly() throws {
        let recipe = fixture.populatedRecipe()

        let encoded = try #require(RecipeTransferEncoder.payload(for: [recipe]).recipes.first)

        #expect(encoded.collectionNames == ["Christmas", "Gifts"])
    }

    @Test func payload_UnfiledRecipe_CarriesNoCollections() throws {
        let recipe = fixture.recipe()
        fixture.addOil(fixture.oil("Olive Oil"), percentage: 100, to: recipe)

        let encoded = try #require(RecipeTransferEncoder.payload(for: [recipe]).recipes.first)

        #expect(encoded.collectionNames.isEmpty)
    }

    // MARK: - Photos

    @Test func fileData_RecipeAndIngredientWithPhotos_ContainsNoImageBytes() throws {
        let recipe = fixture.recipe()
        let oil = fixture.oil("Olive Oil")
        fixture.addOil(oil, percentage: 100, to: recipe)

        let recipePhoto = Data("a-private-photo-of-my-kitchen".utf8)
        let ingredientPhoto = Data("a-photo-of-my-oil-bottle".utf8)
        recipe.imageData = recipePhoto
        recipe.thumbnailData = recipePhoto
        oil.imageData = ingredientPhoto
        oil.thumbnailData = ingredientPhoto

        let json = try #require(String(data: try RecipeTransferEncoder.fileData(for: [recipe]), encoding: .utf8))

        #expect(!json.contains(recipePhoto.base64EncodedString()))
        #expect(!json.contains(ingredientPhoto.base64EncodedString()))
        #expect(!json.lowercased().contains("imagedata"))
        #expect(!json.lowercased().contains("thumbnail"))
    }

    // MARK: - Multiple recipes

    @Test func payload_FifteenRecipes_AllTravelInOnePayload() throws {
        let recipes = (1...15).map { index -> Recipe in
            let recipe = fixture.recipe(named: "Bar \(index)")
            fixture.addOil(fixture.oil("Olive Oil \(index)"), percentage: 100, to: recipe)
            return recipe
        }
        fixture.context.processPendingChanges()

        let payload = RecipeTransferEncoder.payload(for: recipes)

        #expect(payload.recipes.count == 15)
        #expect(payload.recipes.map(\.name) == recipes.map(\.name))
    }

    @Test func payload_RecipesSharingAnOil_PoolTheIngredientOnce() throws {
        let shared = fixture.oil("Olive Oil")
        let first = fixture.recipe(named: "First")
        let second = fixture.recipe(named: "Second")
        fixture.addOil(shared, percentage: 100, to: first)
        fixture.addOil(shared, percentage: 100, to: second)
        fixture.context.processPendingChanges()

        let payload = RecipeTransferEncoder.payload(for: [first, second])

        #expect(payload.ingredients.count == 1)
        #expect(payload.recipes.allSatisfy { $0.ingredients.allSatisfy { $0.ingredientIndex == 0 } })
    }

    @Test func payload_NoRecipes_ProducesAnEmptyPayload() {
        let payload = RecipeTransferEncoder.payload(for: [])

        #expect(payload.recipes.isEmpty)
        #expect(payload.ingredients.isEmpty)
        #expect(payload.version == RecipeTransferData.currentVersion)
    }

    // MARK: - Determinism

    @Test func fileData_SameRecipeTwice_ProducesIdenticalBytes() throws {
        let recipe = fixture.populatedRecipe()
        let exportedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let first = try RecipeTransferEncoder.fileData(for: [recipe], exportedAt: exportedAt)
        let second = try RecipeTransferEncoder.fileData(for: [recipe], exportedAt: exportedAt)

        #expect(first == second)
    }
}
