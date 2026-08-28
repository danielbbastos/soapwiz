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
@MainActor
@Suite
struct RecipeTransferRoundTripTests {

    private let source: RecipeTransferFixture
    private let destination: RecipeTransferFixture

    init() throws {
        source = try RecipeTransferFixture()
        destination = try RecipeTransferFixture()
    }

    // MARK: - Helpers

    /// Exports from the sender's store and imports into the recipient's,
    /// through the file transport.
    @discardableResult
    private func roundTrip(_ recipes: [Recipe], collections: [RecipeCollection] = []) throws -> [Recipe] {
        source.context.processPendingChanges()
        let data = try RecipeTransferEncoder.fileData(for: recipes)
        let payload = try RecipeTransferDecoder.payload(fromFile: data)
        return try importIntoDestination(payload, collections: collections)
    }

    @discardableResult
    private func importIntoDestination(
        _ payload: RecipeTransferData,
        collections: [RecipeCollection] = []
    ) throws -> [Recipe] {
        let inventory = try destination.context.fetch(FetchDescriptor<Ingredient>())
        let categories = try destination.context.fetch(FetchDescriptor<IngredientCategory>())
        let existing = try destination.context.fetch(FetchDescriptor<Recipe>())
        let plan = RecipeTransferPlan(
            payload: payload,
            inventory: inventory,
            collections: collections,
            recipes: existing
        )
        let imported = RecipeTransferImporter.apply(plan, into: destination.context, categories: categories)
        destination.context.processPendingChanges()
        return imported
    }

    // MARK: - Every configuration field

    @Test func roundTrip_PopulatedRecipe_RestoresEveryConfigurationField() throws {
        let original = source.populatedRecipe()

        let imported = try #require(try roundTrip([original]).first)

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

        let imported = try #require(try roundTrip([original]).first)

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

        let imported = try #require(try roundTrip([original]).first)

        #expect(imported.isCreamSoap)
        #expect(!imported.useCFM)
    }

    @Test func roundTrip_CFMRecipe_RestoresTheNeutralizer() throws {
        let original = source.recipe(named: "Liquid Soap")
        original.useCFM = true
        original.cfmNeutralizer = CFMNeutralizer.borax.rawValue
        source.addOil(source.oil("Coconut Oil"), percentage: 100, to: original)

        let imported = try #require(try roundTrip([original]).first)

        #expect(imported.useCFM)
        #expect(imported.cfmNeutralizer == CFMNeutralizer.borax.rawValue)
    }

    @Test func roundTrip_NonSoapRecipe_RestoresItsKind() throws {
        let original = source.recipe(named: "Beeswax Candle")
        original.recipeKind = RecipeKind.general.rawValue
        source.addOil(source.oil("Beeswax"), percentage: 100, to: original)

        let imported = try #require(try roundTrip([original]).first)

        #expect(RecipeKind.resolve(imported.recipeKind) == .general)
    }

    // MARK: - Line items and products

    @Test func roundTrip_LineItems_RestoreRolesAmountsAndUnits() throws {
        let original = source.populatedRecipe()

        let imported = try #require(try roundTrip([original]).first)

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

        let imported = try #require(try roundTrip([original]).first)

        #expect(imported.products.count == 2)
        #expect(imported.products.contains { $0.size == 100 && $0.unitSymbol == "g" })
        #expect(imported.products.contains { $0.unitSymbol == ProductUnit.partsOfBatch.rawValue })
    }

    /// The lye weight the recipient calculates has to be the one the sender saw.
    /// Every field above exists to make this true; this asserts the result
    /// rather than the inputs.
    @Test func roundTrip_PopulatedRecipe_CalculatesTheSameLyeWeight() throws {
        let original = source.populatedRecipe()
        let imported = try #require(try roundTrip([original]).first)

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

        let imported = try roundTrip(originals)

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

        try roundTrip(recipes)

        let olives = try destination.context.fetch(FetchDescriptor<Ingredient>())
            .filter { $0.name == "Olive Oil" }
        #expect(olives.count == 1)
    }

    // MARK: - Ingredient resolution

    @Test func roundTrip_IngredientMissingHere_IsCreatedWithTheSendersChemistry() throws {
        let original = source.recipe()
        source.addOil(
            source.oil("Rare Exotic Oil", sap: 0.1401, kohSap: 0.1962, density: 0.923),
            percentage: 100,
            to: original
        )

        try roundTrip([original])

        let created = try #require(
            try destination.context.fetch(FetchDescriptor<Ingredient>()).first { $0.name == "Rare Exotic Oil" }
        )
        #expect(created.sapValue == 0.1401)
        #expect(created.kohSapValue == 0.1962)
        #expect(created.density == 0.923)
        #expect(created.fattyAcidProfile == .mock)
        #expect(created.unit == "g")
    }

    /// `IngredientFormView` has no fields for these two, so the payload is the
    /// only way they can ever reach a created ingredient.
    @Test func roundTrip_CreatedIngredient_KeepsTheValuesNoFormCanEnter() throws {
        let original = source.recipe()
        source.addOil(source.oil("Rare Exotic Oil", kohSap: 0.1962, profile: .mock), percentage: 100, to: original)

        try roundTrip([original])

        let created = try #require(
            try destination.context.fetch(FetchDescriptor<Ingredient>()).first { $0.name == "Rare Exotic Oil" }
        )
        #expect(created.kohSapValue == 0.1962)
        #expect(created.fattyAcidProfile?.lauric == 1)
        #expect(created.fattyAcidProfile?.ricinoleic == 8)
    }

    @Test func roundTrip_IngredientAlreadyHere_IsMatchedNotDuplicated() throws {
        let mine = destination.oil("Olive Oil", sap: 0.1345)
        destination.context.processPendingChanges()

        let original = source.recipe()
        source.addOil(source.oil("Olive Oil", sap: 0.1345), percentage: 100, to: original)

        let imported = try #require(try roundTrip([original]).first)

        let olives = try destination.context.fetch(FetchDescriptor<Ingredient>()).filter { $0.name == "Olive Oil" }
        #expect(olives.count == 1)
        #expect(imported.ingredients.first?.ingredient === mine)
    }

    @Test func roundTrip_NameDifferingOnlyByCase_StillMatches() throws {
        destination.oil("OLIVE OIL", sap: 0.1345)
        destination.context.processPendingChanges()

        let original = source.recipe()
        source.addOil(source.oil("Olive Oil", sap: 0.1345), percentage: 100, to: original)

        try roundTrip([original])

        let olives = try destination.context.fetch(FetchDescriptor<Ingredient>())
            .filter { $0.name.lookupKey == "olive oil".lookupKey }
        #expect(olives.count == 1)
    }

    /// The recipient's shelf is the authority on the recipient's shelf. An
    /// incoming recipe must never rewrite the chemistry every other recipe in
    /// the library already depends on.
    @Test func roundTrip_MatchedIngredientWithDifferentChemistry_KeepsTheRecipientsValues() throws {
        let mine = destination.oil("Olive Oil", sap: 0.1345, kohSap: 0.1885, density: 0.911)
        destination.context.processPendingChanges()

        let original = source.recipe()
        source.addOil(source.oil("Olive Oil", sap: 0.9999, kohSap: 0.8888, density: 0.7), percentage: 100, to: original)

        try roundTrip([original])

        #expect(mine.sapValue == 0.1345)
        #expect(mine.kohSapValue == 0.1885)
        #expect(mine.density == 0.911)
    }

    @Test func roundTrip_CreatedIngredient_IsFiledUnderTheCategoryItsRoleImplies() throws {
        destination.context.insert(IngredientCategory(name: IngredientCategory.Name.oils))
        destination.context.insert(IngredientCategory(name: IngredientCategory.Name.fragrances))
        destination.context.insert(IngredientCategory(name: IngredientCategory.Name.additives))
        destination.context.processPendingChanges()

        let original = source.populatedRecipe()

        try roundTrip([original])

        let created = try destination.context.fetch(FetchDescriptor<Ingredient>())
        #expect(created.first { $0.name == "Olive Oil" }?.category?.name == IngredientCategory.Name.oils)
        #expect(
            created.first { $0.name == "Lavender Essential Oil" }?.category?.name
                == IngredientCategory.Name.fragrances
        )
        #expect(created.first { $0.name == "Sodium Lactate" }?.category?.name == IngredientCategory.Name.additives)
    }

    // MARK: - Names

    /// Importing a recipe you already have must not leave two rows the user
    /// can't tell apart. The saved recipe carries the suffixed name, not just
    /// the review screen.
    @Test func roundTrip_NameAlreadyInTheLibrary_SavesUnderACopyName() throws {
        let mine = destination.recipe(named: "Lavender Bar")
        destination.addOil(destination.oil("Olive Oil"), percentage: 100, to: mine)
        destination.context.processPendingChanges()

        let imported = try #require(try roundTrip([source.populatedRecipe(named: "Lavender Bar")]).first)

        #expect(imported.name == "Lavender Bar (copy)")
        #expect(mine.name == "Lavender Bar")
        let names = try destination.context.fetch(FetchDescriptor<Recipe>()).map(\.name).sorted()
        #expect(names == ["Lavender Bar", "Lavender Bar (copy)"])
    }

    @Test func roundTrip_NameNotInTheLibrary_KeepsItsOwnName() throws {
        let imported = try #require(try roundTrip([source.populatedRecipe(named: "Brand New Bar")]).first)

        #expect(imported.name == "Brand New Bar")
    }

    /// Everything but the name still comes through: the rename must not be a
    /// different recipe, only a differently-labelled one.
    @Test func roundTrip_RenamedRecipe_KeepsEveryOtherField() throws {
        let mine = destination.recipe(named: "Round Trip Bar")
        destination.context.processPendingChanges()
        let original = source.populatedRecipe(named: "Round Trip Bar")

        let imported = try #require(try roundTrip([original]).first)

        #expect(imported.name == "Round Trip Bar (copy)")
        #expect(mine.name == "Round Trip Bar")
        #expect(imported.desc == original.desc)
        #expect(imported.totalOilWeight == original.totalOilWeight)
        #expect(imported.useHybrid == original.useHybrid)
        #expect(imported.ingredients.count == original.ingredients.count)
    }

    // MARK: - Collections

    @Test func roundTrip_CollectionTheRecipientHas_FilesTheRecipeUnderIt() throws {
        let mine = destination.collection("Christmas")
        destination.context.processPendingChanges()

        let original = source.populatedRecipe()

        let imported = try #require(try roundTrip([original], collections: [mine]).first)

        #expect(imported.collections.count == 1)
        #expect(imported.collections.first === mine)
    }

    /// Filing is a personal decision. An import must not litter someone's
    /// library with a stranger's folders.
    @Test func roundTrip_CollectionTheRecipientLacks_CreatesNothingAndLeavesItUnfiled() throws {
        let original = source.populatedRecipe()

        let imported = try #require(try roundTrip([original]).first)

        #expect(imported.collections.isEmpty)
        #expect(try destination.context.fetch(FetchDescriptor<RecipeCollection>()).isEmpty)
    }

    @Test func roundTrip_SomeCollectionsMatching_FilesUnderOnlyThose() throws {
        let christmas = destination.collection("Christmas")
        destination.context.processPendingChanges()

        let original = source.populatedRecipe()

        let imported = try #require(try roundTrip([original], collections: [christmas]).first)

        #expect(imported.collections.map(\.name) == ["Christmas"])
    }

    // MARK: - Photos

    @Test func roundTrip_RecipeWithAPhoto_ArrivesWithoutOne() throws {
        let original = source.populatedRecipe()
        original.imageData = Data("a-private-photo".utf8)
        original.thumbnailData = original.imageData

        let imported = try #require(try roundTrip([original]).first)

        #expect(imported.imageData == nil)
        #expect(imported.thumbnailData == nil)
    }

    @Test func roundTrip_IngredientWithAPhoto_ArrivesWithoutOne() throws {
        let original = source.recipe()
        let oil = source.oil("Rare Exotic Oil")
        oil.imageData = Data("a-photo-of-my-bottle".utf8)
        oil.thumbnailData = oil.imageData
        source.addOil(oil, percentage: 100, to: original)

        try roundTrip([original])

        let created = try #require(
            try destination.context.fetch(FetchDescriptor<Ingredient>()).first { $0.name == "Rare Exotic Oil" }
        )
        #expect(created.imageData == nil)
        #expect(created.thumbnailData == nil)
    }

    // MARK: - What is deliberately not carried

    @Test func roundTrip_FavouritedRecipe_ArrivesUnfavourited() throws {
        let original = source.populatedRecipe()
        original.isFavorite = true

        let imported = try #require(try roundTrip([original]).first)

        #expect(!imported.isFavorite)
    }

    @Test func roundTrip_IngredientWithPurchases_ArrivesWithNoStockOrCost() throws {
        let original = source.recipe()
        let oil = source.oil("Rare Exotic Oil")
        let purchase = IngredientPurchase(
            dateOfPurchase: .now,
            quantity: 1000,
            totalPrice: 42,
            badge: "",
            journalCode: "",
            expiryDate: nil,
            openingDate: nil
        )
        purchase.ingredient = oil
        source.context.insert(purchase)
        source.addOil(oil, percentage: 100, to: original)

        try roundTrip([original])

        let created = try #require(
            try destination.context.fetch(FetchDescriptor<Ingredient>()).first { $0.name == "Rare Exotic Oil" }
        )
        #expect(created.purchases.isEmpty)
        #expect(try destination.context.fetch(FetchDescriptor<IngredientPurchase>()).isEmpty)
    }

    /// The sender's costing ingredient means nothing on another device, and the
    /// recipient's form resolves its own.
    @Test func roundTrip_RecipeWithLyeIngredient_ArrivesWithoutIt() throws {
        let original = source.recipe()
        original.lyeIngredient = source.oil("Sodium Hydroxide", sap: nil, kohSap: nil, density: nil, profile: nil)
        source.addOil(source.oil("Olive Oil"), percentage: 100, to: original)

        let imported = try #require(try roundTrip([original]).first)

        #expect(imported.lyeIngredient == nil)
        #expect(
            try destination.context.fetch(FetchDescriptor<Ingredient>())
                .allSatisfy { $0.name != "Sodium Hydroxide" }
        )
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
        let imported = try #require(try importIntoDestination(payload).first)

        #expect(imported.name == original.name)
        #expect(imported.useHybrid == original.useHybrid)
        #expect(imported.isCreamSoap == original.isCreamSoap)
        #expect(imported.useCFM == original.useCFM)
        #expect(imported.ingredients.count == original.ingredients.count)
        #expect(imported.products.count == original.products.count)
    }
}
