import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// "Copy Recipe" serving both audiences at once: the payload is readable by the
/// importer, and the text above it is still readable by a person.
@MainActor
@Suite
struct RecipeClipboardExportTests {

    private let fixture: RecipeTransferFixture

    init() throws {
        fixture = try RecipeTransferFixture()
    }

    @Test func clipboardText_Always_EndsWithTheMarkerOnItsOwnLine() throws {
        let recipe = fixture.populatedRecipe()

        let lines = RecipeTextExporter.clipboardText(for: recipe).components(separatedBy: "\n")

        let last = try #require(lines.last)
        #expect(RecipeTransferMarker.isMarkerLine(last))
        #expect(lines.filter(RecipeTransferMarker.isMarkerLine).count == 1)
    }

    /// The readable half is what someone pastes into a forum post, and it must
    /// not have changed just because the payload now rides along behind it.
    @Test func clipboardText_WithoutItsFinalLine_IsExactlyTheReadableText() throws {
        let recipe = fixture.populatedRecipe()

        let clipboard = RecipeTextExporter.clipboardText(for: recipe)
        let withoutMarker = clipboard
            .components(separatedBy: "\n")
            .filter { !RecipeTransferMarker.isMarkerLine($0) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(withoutMarker == RecipeTextExporter.text(for: recipe))
    }

    @Test func clipboardText_Always_ReadsBackAsTheSameRecipe() throws {
        let recipe = fixture.populatedRecipe()

        let outcome = RecipeTransferMarker.scan(RecipeTextExporter.clipboardText(for: recipe))

        guard case .payload(let payload) = outcome else {
            Issue.record("Expected the clipboard text to carry a payload, got \(outcome)")
            return
        }
        let encoded = try #require(payload.recipes.first)
        #expect(encoded.name == recipe.name)
        #expect(encoded.useHybrid == recipe.useHybrid)
        #expect(encoded.isCreamSoap == recipe.isCreamSoap)
        #expect(encoded.useCFM == recipe.useCFM)
        #expect(encoded.collectionNames == ["Christmas", "Gifts"])
        #expect(payload.ingredients.count == 5)
    }

    @Test func clipboardText_NonSoapRecipe_CarriesItsKind() throws {
        let recipe = fixture.recipe(named: "Beeswax Candle")
        recipe.recipeKind = RecipeKind.general.rawValue
        fixture.addOil(fixture.oil("Beeswax"), percentage: 100, to: recipe)
        fixture.context.processPendingChanges()

        let outcome = RecipeTransferMarker.scan(RecipeTextExporter.clipboardText(for: recipe))

        guard case .payload(let payload) = outcome else {
            Issue.record("Expected the clipboard text to carry a payload, got \(outcome)")
            return
        }
        #expect(payload.recipes.first?.kind == .general)
    }

    /// The marker is base64 nobody can read and the model has no use for. Left
    /// in, it would spend a sixth of the character budget on nothing.
    @Test func sanitize_TextEndingInAMarker_DropsTheMarkerLine() throws {
        let recipe = fixture.populatedRecipe()
        let clipboard = RecipeTextExporter.clipboardText(for: recipe)

        let sanitized = RecipeTextSanitizer.sanitize(clipboard)

        #expect(!sanitized.text.contains(RecipeTransferMarker.prefix))
        #expect(sanitized.text.contains("Olive Oil"))
    }

    @Test func sanitize_TextEndingInAMarker_LeavesTheRecipeIntact() throws {
        let recipe = fixture.populatedRecipe()

        let withMarker = RecipeTextSanitizer.sanitize(RecipeTextExporter.clipboardText(for: recipe))
        let withoutMarker = RecipeTextSanitizer.sanitize(RecipeTextExporter.text(for: recipe))

        #expect(withMarker.text == withoutMarker.text)
    }

    /// The box the user sees keeps the marker: it is what the importer scans.
    @Test func tidiedForEditing_TextWithMarker_KeepsIt() throws {
        let recipe = fixture.populatedRecipe()
        let clipboard = RecipeTextExporter.clipboardText(for: recipe)

        let tidied = RecipeTextSanitizer.tidiedForEditing(clipboard)

        #expect(RecipeTransferMarker.scan(tidied) != RecipeTransferScan.none)
    }
}
