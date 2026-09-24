import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The payload surviving each transport unchanged, and the version gates that
/// stop it being read when it shouldn't be.
@MainActor
@Suite
struct RecipeTransferCodecTests {

    private let fixture: RecipeTransferFixture

    init() throws {
        fixture = try RecipeTransferFixture()
    }

    // MARK: - File transport

    @Test func fileRoundTrip_PopulatedRecipe_DecodesIdentically() throws {
        let payload = RecipeTransferEncoder.payload(for: [fixture.populatedRecipe()])

        let data = try RecipeTransferCoding.encoder.encode(payload)
        let decoded = try RecipeTransferDecoder.payload(fromFile: data)

        #expect(decoded == payload)
    }

    @Test func fileRoundTrip_FifteenRecipes_DecodeIdentically() throws {
        let recipes = (1...15).map { index -> Recipe in
            let recipe = fixture.populatedRecipe(named: "Bar \(index)")
            return recipe
        }
        fixture.context.processPendingChanges()
        let payload = RecipeTransferEncoder.payload(for: recipes)

        let decoded = try RecipeTransferDecoder.payload(fromFile: try RecipeTransferCoding.encoder.encode(payload))

        #expect(decoded.recipes.count == 15)
        #expect(decoded == payload)
    }

    /// A payload written before the identity field existed has no `uuid` key at
    /// all. Stripping it from a current file is the closest honest stand-in, and
    /// it must still decode — the format's backward compatibility is the whole
    /// reason the field is optional.
    @Test func payloadFromFile_RecipeWithoutAUUIDKey_StillDecodes() throws {
        let data = try RecipeTransferEncoder.fileData(for: [fixture.populatedRecipe()])
        var object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var recipes = try #require(object["recipes"] as? [[String: Any]])
        recipes = recipes.map { recipe in
            var stripped = recipe
            stripped.removeValue(forKey: "uuid")
            return stripped
        }
        object["recipes"] = recipes
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try RecipeTransferDecoder.payload(fromFile: legacy)

        #expect(decoded.recipes.count == 1)
        #expect(decoded.recipes.first?.uuid == nil)
        #expect(decoded.recipes.first?.name == "Round Trip Bar")
    }

    @Test func fileRoundTrip_Recipe_KeepsItsIdentity() throws {
        let recipe = fixture.populatedRecipe()
        let payload = RecipeTransferEncoder.payload(for: [recipe])

        let decoded = try RecipeTransferDecoder.payload(fromFile: try RecipeTransferCoding.encoder.encode(payload))

        #expect(decoded.recipes.first?.uuid == recipe.uuid)
    }

    @Test func payloadFromFile_NotJSON_ThrowsMalformed() {
        #expect(throws: RecipeTransferError.malformedFile) {
            try RecipeTransferDecoder.payload(fromFile: Data("not a recipe file".utf8))
        }
    }

    @Test func payloadFromFile_TruncatedJSON_ThrowsMalformed() throws {
        let data = try RecipeTransferEncoder.fileData(for: [fixture.populatedRecipe()])
        let truncated = data.prefix(data.count / 2)

        #expect(throws: RecipeTransferError.malformedFile) {
            try RecipeTransferDecoder.payload(fromFile: Data(truncated))
        }
    }

    @Test func payloadFromFile_NewerVersion_ThrowsUnsupportedVersion() throws {
        var payload = RecipeTransferEncoder.payload(for: [fixture.populatedRecipe()])
        payload.version = RecipeTransferData.currentVersion + 1
        let data = try RecipeTransferCoding.encoder.encode(payload)

        #expect(throws: RecipeTransferError.unsupportedVersion(
            found: RecipeTransferData.currentVersion + 1,
            supported: RecipeTransferData.currentVersion
        )) {
            try RecipeTransferDecoder.payload(fromFile: data)
        }
    }

    /// A line item pointing past the end of the ingredient pool would trap on
    /// subscript, so it is refused before anything reads it.
    @Test func payloadFromFile_LineItemIndexOutOfRange_ThrowsMalformed() throws {
        var payload = RecipeTransferEncoder.payload(for: [fixture.populatedRecipe()])
        payload.recipes[0].ingredients[0].ingredientIndex = 99
        let data = try RecipeTransferCoding.encoder.encode(payload)

        #expect(throws: RecipeTransferError.malformedFile) {
            try RecipeTransferDecoder.payload(fromFile: data)
        }
    }
}
