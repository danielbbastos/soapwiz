import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// What an imported recipe's ingredients and collections resolve to on the
/// receiving side, and what the payload deliberately doesn't carry.
///
/// Split from `RecipeTransferRoundTripTests`, which asserts the recipe's own
/// fields survive. Both take the same trip; these assert what it touched on
/// arrival.
@MainActor
@Suite
struct RecipeTransferResolutionTests {

    private let harness: RecipeTransferRoundTripHarness
    private var source: RecipeTransferFixture { harness.source }
    private var destination: RecipeTransferFixture { harness.destination }

    init() throws {
        harness = try RecipeTransferRoundTripHarness()
    }

    // MARK: - Ingredient resolution

    @Test func roundTrip_IngredientMissingHere_IsCreatedWithTheSendersChemistry() throws {
        let original = source.recipe()
        source.addOil(
            source.oil("Rare Exotic Oil", sap: 0.1401, kohSap: 0.1962, density: 0.923),
            percentage: 100,
            to: original
        )

        try harness.roundTrip([original])

        let created = try #require(
            try harness.received(Ingredient.self).first { $0.name == "Rare Exotic Oil" }
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

        try harness.roundTrip([original])

        let created = try #require(
            try harness.received(Ingredient.self).first { $0.name == "Rare Exotic Oil" }
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

        let imported = try #require(try harness.roundTrip([original]).first)

        let olives = try harness.received(Ingredient.self).filter { $0.name == "Olive Oil" }
        #expect(olives.count == 1)
        #expect(imported.ingredients.first?.ingredient === mine)
    }

    @Test func roundTrip_NameDifferingOnlyByCase_StillMatches() throws {
        destination.oil("OLIVE OIL", sap: 0.1345)
        destination.context.processPendingChanges()

        let original = source.recipe()
        source.addOil(source.oil("Olive Oil", sap: 0.1345), percentage: 100, to: original)

        try harness.roundTrip([original])

        let olives = try harness.received(Ingredient.self)
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

        try harness.roundTrip([original])

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

        try harness.roundTrip([original])

        let created = try harness.received(Ingredient.self)
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

        let imported = try #require(try harness.roundTrip([source.populatedRecipe(named: "Lavender Bar")]).first)

        #expect(imported.name == "Lavender Bar (copy)")
        #expect(mine.name == "Lavender Bar")
        let names = try harness.received(Recipe.self).map(\.name).sorted()
        #expect(names == ["Lavender Bar", "Lavender Bar (copy)"])
    }

    @Test func roundTrip_NameNotInTheLibrary_KeepsItsOwnName() throws {
        let imported = try #require(try harness.roundTrip([source.populatedRecipe(named: "Brand New Bar")]).first)

        #expect(imported.name == "Brand New Bar")
    }

    /// Everything but the name still comes through: the rename must not be a
    /// different recipe, only a differently-labelled one.
    @Test func roundTrip_RenamedRecipe_KeepsEveryOtherField() throws {
        let mine = destination.recipe(named: "Round Trip Bar")
        destination.context.processPendingChanges()
        let original = source.populatedRecipe(named: "Round Trip Bar")

        let imported = try #require(try harness.roundTrip([original]).first)

        #expect(imported.name == "Round Trip Bar (copy)")
        #expect(mine.name == "Round Trip Bar")
        #expect(imported.desc == original.desc)
        #expect(imported.totalOilWeight == original.totalOilWeight)
        #expect(imported.useHybrid == original.useHybrid)
        #expect(imported.ingredients.count == original.ingredients.count)
    }

    // MARK: - Identity

    /// The identity travels with the recipe. Without this the format carries an
    /// identity nobody can use: a recipe sent to a friend would come back
    /// unrecognisable, which is the case the field exists for.
    @Test func roundTrip_NewRecipe_ArrivesUnderTheSendersIdentity() throws {
        let original = source.populatedRecipe(named: "Lavender Bar")

        let imported = try #require(try harness.roundTrip([original]).first)

        #expect(imported.uuid == original.uuid)
    }

    @Test func roundTrip_FifteenRecipes_EachArrivesUnderItsOwnIdentity() throws {
        let originals = (1...15).map { source.populatedRecipe(named: "Bar \($0)") }
        source.context.processPendingChanges()

        let imported = try harness.roundTrip(originals)

        #expect(imported.map(\.uuid) == originals.map(\.uuid))
    }

    /// The same file imported twice must not leave two rows claiming to be one
    /// recipe — a later payload would match both and neither answer is right.
    @Test func roundTrip_SameRecipeImportedTwice_TheSecondGetsAFreshIdentity() throws {
        let original = source.populatedRecipe(named: "Lavender Bar")

        let first = try #require(try harness.roundTrip([original]).first)
        let second = try #require(try harness.roundTrip([original]).first)

        #expect(first.uuid == original.uuid)
        #expect(second.uuid != original.uuid)
        #expect(second.uuid != first.uuid)
        #expect(Set(try harness.received(Recipe.self).map(\.uuid)).count == 2)
    }

    /// A file holding the same recipe twice — duplicated by hand, or by a sender
    /// who exported a recipe alongside its own copy — must still land as two
    /// distinguishable rows.
    @Test func roundTrip_PayloadCarryingOneIdentityTwice_SplitsThemOnArrival() throws {
        let original = source.populatedRecipe(named: "Lavender Bar")
        var payload = source.payload([original])
        payload.recipes.append(payload.recipes[0])

        let imported = try harness.importIntoDestination(payload)

        #expect(imported.count == 2)
        #expect(Set(imported.map(\.uuid)).count == 2)
    }

    /// Recognising a returning recipe must never touch the copy the user has
    /// been editing.
    @Test func roundTrip_RecipeComingBack_LeavesTheUsersOwnCopyAlone() throws {
        let original = source.populatedRecipe(named: "Lavender Bar")
        let mine = try #require(try harness.roundTrip([original]).first)
        mine.name = "My Own Lavender Bar"
        mine.superFat = 12
        destination.context.processPendingChanges()

        let returned = try #require(try harness.roundTrip([original]).first)

        #expect(mine.name == "My Own Lavender Bar")
        #expect(mine.superFat == 12)
        #expect(mine.uuid == original.uuid)
        #expect(returned.uuid != mine.uuid)
        #expect(try harness.received(Recipe.self).count == 2)
    }

    /// A version-1 payload carries no identity, so the recipe is minted a fresh
    /// one on arrival rather than left without.
    @Test func roundTrip_PayloadWithoutAnIdentity_MintsAFreshOneOnArrival() throws {
        let original = source.populatedRecipe(named: "Lavender Bar")
        var payload = source.payload([original])
        payload.recipes[0].uuid = nil

        let imported = try #require(try harness.importIntoDestination(payload).first)

        #expect(imported.name == "Lavender Bar")
        #expect(imported.uuid != original.uuid)
        #expect(try harness.received(Recipe.self).count == 1)
    }

    /// Two identity-less recipes in one file must not come out sharing one.
    @Test func roundTrip_TwoPayloadRecipesWithoutIdentities_GetDistinctOnes() throws {
        let first = source.populatedRecipe(named: "Bar One")
        let second = source.populatedRecipe(named: "Bar Two")
        source.context.processPendingChanges()
        var payload = source.payload([first, second])
        payload.recipes[0].uuid = nil
        payload.recipes[1].uuid = nil

        let imported = try harness.importIntoDestination(payload)

        #expect(imported.count == 2)
        #expect(Set(imported.map(\.uuid)).count == 2)
    }

    // MARK: - Collections

    @Test func roundTrip_CollectionTheRecipientHas_FilesTheRecipeUnderIt() throws {
        let mine = destination.collection("Christmas")
        destination.context.processPendingChanges()

        let original = source.populatedRecipe()

        let imported = try #require(try harness.roundTrip([original], collections: [mine]).first)

        #expect(imported.collections.count == 1)
        #expect(imported.collections.first === mine)
    }

    /// Filing is a personal decision. An import must not litter someone's
    /// library with a stranger's folders.
    @Test func roundTrip_CollectionTheRecipientLacks_CreatesNothingAndLeavesItUnfiled() throws {
        let original = source.populatedRecipe()

        let imported = try #require(try harness.roundTrip([original]).first)

        #expect(imported.collections.isEmpty)
        #expect(try harness.received(RecipeCollection.self).isEmpty)
    }

    /// Two names can resolve to one collection: a sender with an unmerged
    /// CloudKit duplicate files a recipe under both "Gifts" rows, so the payload
    /// carries the name twice and both lookups land on the single match here.
    ///
    /// The importer does nothing about this — the relationship itself collapses
    /// the repeat, so assigning the same collection twice files the recipe once.
    /// Pinned because that is a property of SwiftData rather than of anything
    /// visible in `RecipeTransferImporter`: the day the assignment changes shape,
    /// the recipe would start drawing its chip twice with nothing else to catch it.
    @Test func roundTrip_SenderHadDuplicateCollections_FilesTheRecipeOnce() throws {
        let mine = destination.collection("Gifts")
        destination.context.processPendingChanges()

        let original = source.recipe(named: "Doubly Filed")
        source.addOil(source.oil("Olive Oil"), percentage: 100, to: original)
        original.collections = [source.collection("Gifts"), source.collection("Gifts")]
        source.context.processPendingChanges()

        // The payload really does carry the name twice — the precondition this
        // test exists for.
        let payload = RecipeTransferEncoder.payload(for: [original])
        #expect(payload.recipes.first?.collectionNames == ["Gifts", "Gifts"])

        let imported = try #require(try harness.importIntoDestination(payload, collections: [mine]).first)

        #expect(imported.collections.count == 1)
        #expect(imported.collections.first === mine)
    }

    @Test func roundTrip_SomeCollectionsMatching_FilesUnderOnlyThose() throws {
        let christmas = destination.collection("Christmas")
        destination.context.processPendingChanges()

        let original = source.populatedRecipe()

        let imported = try #require(try harness.roundTrip([original], collections: [christmas]).first)

        #expect(imported.collections.map(\.name) == ["Christmas"])
    }

    // MARK: - Photos

    @Test func roundTrip_RecipeWithAPhoto_ArrivesWithoutOne() throws {
        let original = source.populatedRecipe()
        original.imageData = Data("a-private-photo".utf8)
        original.thumbnailData = original.imageData

        let imported = try #require(try harness.roundTrip([original]).first)

        #expect(imported.imageData == nil)
        #expect(imported.thumbnailData == nil)
    }

    @Test func roundTrip_IngredientWithAPhoto_ArrivesWithoutOne() throws {
        let original = source.recipe()
        let oil = source.oil("Rare Exotic Oil")
        oil.imageData = Data("a-photo-of-my-bottle".utf8)
        oil.thumbnailData = oil.imageData
        source.addOil(oil, percentage: 100, to: original)

        try harness.roundTrip([original])

        let created = try #require(
            try harness.received(Ingredient.self).first { $0.name == "Rare Exotic Oil" }
        )
        #expect(created.imageData == nil)
        #expect(created.thumbnailData == nil)
    }

    // MARK: - What is deliberately not carried

    @Test func roundTrip_FavouritedRecipe_ArrivesUnfavourited() throws {
        let original = source.populatedRecipe()
        original.isFavorite = true

        let imported = try #require(try harness.roundTrip([original]).first)

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

        try harness.roundTrip([original])

        let created = try #require(
            try harness.received(Ingredient.self).first { $0.name == "Rare Exotic Oil" }
        )
        #expect(created.purchases.isEmpty)
        #expect(try harness.received(IngredientPurchase.self).isEmpty)
    }

    /// The sender's costing ingredient means nothing on another device, and the
    /// recipient's form resolves its own.
    @Test func roundTrip_RecipeWithLyeIngredient_ArrivesWithoutIt() throws {
        let original = source.recipe()
        original.lyeIngredient = source.oil("Sodium Hydroxide", sap: nil, kohSap: nil, density: nil, profile: nil)
        source.addOil(source.oil("Olive Oil"), percentage: 100, to: original)

        let imported = try #require(try harness.roundTrip([original]).first)

        #expect(imported.lyeIngredient == nil)
        #expect(
            try harness.received(Ingredient.self)
                .allSatisfy { $0.name != "Sodium Hydroxide" }
        )
    }
}
