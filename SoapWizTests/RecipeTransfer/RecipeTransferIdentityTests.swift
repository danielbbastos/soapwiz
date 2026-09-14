import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Which identity an imported recipe is saved under on the receiving side.
///
/// Split from `RecipeTransferResolutionTests`, which asserts what the recipe's
/// ingredients and collections resolve to. Both take the same trip; these
/// assert the recipe arrives as itself without ever sharing an identity.
@MainActor
@Suite
struct RecipeTransferIdentityTests {

    private let harness: RecipeTransferRoundTripHarness
    private var source: RecipeTransferFixture { harness.source }
    private var destination: RecipeTransferFixture { harness.destination }

    init() throws {
        harness = try RecipeTransferRoundTripHarness()
    }

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
}
