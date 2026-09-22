import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The two copy actions: "Copy for SoapWiz" (`soapwizText`) puts only the exact
/// payload on the clipboard, and "Copy Recipe" (`text`) puts only readable text.
@MainActor
@Suite
struct RecipeClipboardExportTests {

    private let fixture: RecipeTransferFixture

    init() throws {
        fixture = try RecipeTransferFixture()
    }

    /// "Copy for SoapWiz" is the marker and nothing else — no readable body for
    /// the importer to wade through.
    @Test func soapwizText_Always_IsTheMarkerLineAlone() throws {
        let recipe = fixture.populatedRecipe()

        let lines = RecipeTextExporter.soapwizText(for: recipe).components(separatedBy: "\n")

        #expect(lines.count == 1)
        let only = try #require(lines.first)
        #expect(RecipeTransferMarker.isMarkerLine(only))
    }

    /// None of the readable recipe leaks into the SoapWiz copy — that is what
    /// "Copy Recipe" is for.
    @Test func soapwizText_CarriesNoneOfTheReadableText() throws {
        let recipe = fixture.populatedRecipe()

        let soapwiz = RecipeTextExporter.soapwizText(for: recipe)

        #expect(!soapwiz.contains("Olive Oil"))
        #expect(!soapwiz.contains(recipe.name))
    }

    @Test func soapwizText_Always_ReadsBackAsTheSameRecipe() throws {
        let recipe = fixture.populatedRecipe()

        let outcome = RecipeTransferMarker.scan(RecipeTextExporter.soapwizText(for: recipe))

        guard case .payload(let payload) = outcome else {
            Issue.record("Expected the SoapWiz copy to carry a payload, got \(outcome)")
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

    /// "Copy Recipe" is the person-facing copy: readable text with none of the
    /// base64 marker the importer rides along on.
    @Test func text_Always_CarriesNoImportMarker() throws {
        let recipe = fixture.populatedRecipe()

        let readable = RecipeTextExporter.text(for: recipe)

        #expect(!readable.contains(RecipeTransferMarker.prefix))
        #expect(RecipeTransferMarker.scan(readable) == RecipeTransferScan.none)
    }

    @Test func soapwizText_NonSoapRecipe_CarriesItsKind() throws {
        let recipe = fixture.recipe(named: "Beeswax Candle")
        recipe.recipeKind = RecipeKind.general.rawValue
        fixture.addOil(fixture.oil("Beeswax"), percentage: 100, to: recipe)
        fixture.context.processPendingChanges()

        let outcome = RecipeTransferMarker.scan(RecipeTextExporter.soapwizText(for: recipe))

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
        let combined = try fixture.combinedText(for: recipe)

        let sanitized = RecipeTextSanitizer.sanitize(combined)

        #expect(!sanitized.text.contains(RecipeTransferMarker.prefix))
        #expect(sanitized.text.contains("Olive Oil"))
    }

    @Test func sanitize_TextEndingInAMarker_LeavesTheRecipeIntact() throws {
        let recipe = fixture.populatedRecipe()

        let withMarker = RecipeTextSanitizer.sanitize(try fixture.combinedText(for: recipe))
        let withoutMarker = RecipeTextSanitizer.sanitize(RecipeTextExporter.text(for: recipe))

        #expect(withMarker.text == withoutMarker.text)
    }

    /// The box the user sees keeps the marker: it is what the importer scans.
    @Test func tidiedForEditing_TextWithMarker_KeepsIt() throws {
        let recipe = fixture.populatedRecipe()
        let soapwiz = RecipeTextExporter.soapwizText(for: recipe)

        let tidied = RecipeTextSanitizer.tidiedForEditing(soapwiz)

        #expect(RecipeTransferMarker.scan(tidied) != RecipeTransferScan.none)
    }
}
