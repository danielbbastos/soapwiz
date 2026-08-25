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

    // MARK: - Clipboard transport

    @Test func clipboardRoundTrip_PopulatedRecipe_DecodesIdentically() throws {
        let payload = RecipeTransferEncoder.payload(for: [fixture.populatedRecipe()])
        let line = try #require(RecipeTransferMarker.line(for: payload))

        #expect(RecipeTransferMarker.scan(line) == .payload(payload))
    }

    @Test func markerLine_Always_IsASingleLineOfURLSafeCharacters() throws {
        let payload = RecipeTransferEncoder.payload(for: [fixture.populatedRecipe()])

        let line = try #require(RecipeTransferMarker.line(for: payload))

        #expect(!line.contains("\n"))
        #expect(line.hasPrefix("SOAPWIZ-RECIPE-V1:"))
        let blob = line.dropFirst("SOAPWIZ-RECIPE-V1:".count)
        #expect(!blob.isEmpty)
        // base64url: `+`, `/` and `=` are what get escaped or stripped in transit.
        #expect(!blob.contains("+"))
        #expect(!blob.contains("/"))
        #expect(!blob.contains("="))
    }

    @Test func scan_TextWithoutMarker_FindsNothing() {
        #expect(RecipeTransferMarker.scan("Olive Oil 55%\nCoconut Oil 30%") == RecipeTransferScan.none)
    }

    @Test func scan_EmptyText_FindsNothing() {
        #expect(RecipeTransferMarker.scan("") == RecipeTransferScan.none)
    }

    /// A damaged payload is not an error the user should be stopped for: the
    /// readable recipe above it is intact, so the caller falls through to the
    /// language model rather than refusing the import.
    @Test func scan_TruncatedBlob_FallsBackToTheTextPath() throws {
        let payload = RecipeTransferEncoder.payload(for: [fixture.populatedRecipe()])
        let line = try #require(RecipeTransferMarker.line(for: payload))
        let truncated = String(line.prefix(line.count / 2))

        #expect(RecipeTransferMarker.scan(truncated) == RecipeTransferScan.none)
    }

    @Test func scan_BlobWithMangledCharacters_FallsBackToTheTextPath() throws {
        let payload = RecipeTransferEncoder.payload(for: [fixture.populatedRecipe()])
        let line = try #require(RecipeTransferMarker.line(for: payload))

        #expect(RecipeTransferMarker.scan(line.replacingOccurrences(of: "A", with: " ")) == RecipeTransferScan.none)
    }

    @Test func scan_NewerEnvelopeVersion_IsRejectedRatherThanIgnored() {
        let outcome = RecipeTransferMarker.scan("SOAPWIZ-RECIPE-V9:abcdef")

        #expect(outcome == .rejected(.unsupportedVersion(found: 9, supported: 1)))
    }

    @Test func scan_NewerPayloadVersion_IsRejectedRatherThanIgnored() throws {
        var payload = RecipeTransferEncoder.payload(for: [fixture.populatedRecipe()])
        payload.version = 7
        let line = try #require(RecipeTransferMarker.line(for: payload))

        #expect(RecipeTransferMarker.scan(line) == .rejected(.unsupportedVersion(found: 7, supported: 1)))
    }

    /// Text accumulates as it is forwarded. A reply quoting the original leaves
    /// two markers in the box, and the one nearest the bottom belongs to the
    /// message being imported.
    @Test func scan_TwoMarkers_ReadsTheLast() throws {
        let first = RecipeTransferEncoder.payload(for: [fixture.populatedRecipe(named: "Old")])
        let second = RecipeTransferEncoder.payload(for: [fixture.populatedRecipe(named: "New")])
        let text = """
            \(try #require(RecipeTransferMarker.line(for: first)))

            > quoted reply
            \(try #require(RecipeTransferMarker.line(for: second)))
            """

        #expect(RecipeTransferMarker.scan(text) == .payload(second))
    }

    /// Someone writing *about* the format is not offering a payload.
    @Test func scan_MarkerQuotedMidSentence_FindsNothing() throws {
        let payload = RecipeTransferEncoder.payload(for: [fixture.populatedRecipe()])
        let line = try #require(RecipeTransferMarker.line(for: payload))

        #expect(RecipeTransferMarker.scan("the app writes \(line) at the end") == RecipeTransferScan.none)
    }

    @Test func scan_MarkerWithTrailingWhitespace_StillReads() throws {
        let payload = RecipeTransferEncoder.payload(for: [fixture.populatedRecipe()])
        let line = try #require(RecipeTransferMarker.line(for: payload))

        #expect(RecipeTransferMarker.scan("\(line)   \n") == .payload(payload))
    }

    @Test func isMarkerLine_MarkerOfAnyVersion_IsRecognised() {
        #expect(RecipeTransferMarker.isMarkerLine("SOAPWIZ-RECIPE-V1:abc-_123"))
        #expect(RecipeTransferMarker.isMarkerLine("SOAPWIZ-RECIPE-V9:abc"))
        #expect(!RecipeTransferMarker.isMarkerLine("SOAPWIZ-RECIPE-V1:"))
        #expect(!RecipeTransferMarker.isMarkerLine("SOAPWIZ-RECIPE-VX:abc"))
        #expect(!RecipeTransferMarker.isMarkerLine("Olive Oil 55%"))
    }
}
