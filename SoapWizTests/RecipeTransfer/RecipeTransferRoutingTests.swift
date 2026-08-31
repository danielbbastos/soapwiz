import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// Which of the two paths a given input takes.
///
/// The exact path has to be chosen by looking at what arrived, not by asking the
/// user to declare it — and it has to run without the language model, which is
/// what makes import work on a device Apple Intelligence can't run on.
@MainActor
@Suite
struct RecipeTransferRoutingTests {

    private let fixture: RecipeTransferFixture

    init() throws {
        fixture = try RecipeTransferFixture()
    }

    // MARK: - Routing

    /// The exact path runs without the model even being asked, which is what
    /// makes import work on a device Apple Intelligence can't run on.
    @Test func extract_TextCarryingAPayload_NeverCallsTheExtractor() async throws {
        let extractor = StubRecipeExtractor(error: .modelUnavailable("should not be reached"))
        let model = RecipeImportViewModel(extractor: extractor)
        model.rawText = RecipeTextExporter.clipboardText(for: fixture.populatedRecipe())

        await model.extract(inventory: [], collections: [])

        #expect(model.phase == .exactReview)
        #expect(extractor.recorder.lastText == nil)
        #expect(model.transferPlan != nil)
    }

    @Test func extract_TextWithNoMarker_StillTakesTheLanguageModelPath() async throws {
        var draft = RecipeImportDraft()
        draft.name = "Read By The Model"
        draft.oils = [ImportedIngredient(name: "Olive Oil", amount: 100, unit: nil)]
        let extractor = StubRecipeExtractor(draft: draft)
        let model = RecipeImportViewModel(extractor: extractor)
        model.rawText = "Olive Oil 100%\nSuperfat 5%"

        await model.extract(inventory: fixture.inventoryForImport(), collections: [])

        #expect(model.phase == .review)
        #expect(model.transferPlan == nil)
        #expect(extractor.recorder.lastText != nil)
    }

    /// A recipe mangled in transit should still import approximately: the
    /// readable text above the marker is intact.
    @Test func extract_TruncatedPayload_FallsBackToTheLanguageModel() async throws {
        var draft = RecipeImportDraft()
        draft.oils = [ImportedIngredient(name: "Olive Oil", amount: 100, unit: nil)]
        let extractor = StubRecipeExtractor(draft: draft)
        let model = RecipeImportViewModel(extractor: extractor)
        let clipboard = RecipeTextExporter.clipboardText(for: fixture.populatedRecipe())
        model.rawText = String(clipboard.prefix(clipboard.count - 200))

        await model.extract(inventory: fixture.inventoryForImport(), collections: [])

        #expect(model.phase == .review)
        #expect(extractor.recorder.lastText != nil)
    }

    /// The one case that interrupts rather than falling back: the user has a
    /// real recipe in hand and an app update is what stands between them.
    @Test func extract_PayloadFromANewerVersion_FailsRatherThanGuessing() async throws {
        let extractor = StubRecipeExtractor(error: .modelUnavailable("should not be reached"))
        let model = RecipeImportViewModel(extractor: extractor)
        var newer = fixture.payload([fixture.populatedRecipe()])
        newer.version = RecipeTransferData.currentVersion + 1
        model.rawText = try #require(RecipeTransferMarker.line(for: newer))

        await model.extract(inventory: [], collections: [])

        guard case .failed(let error) = model.phase else {
            Issue.record("Expected a failure, got \(model.phase)")
            return
        }
        #expect(error.errorDescription?.contains("newer version") == true)
        #expect(extractor.recorder.lastText == nil)
    }

    @Test func extract_PayloadWithNoRecipes_ReportsNothingToImport() async throws {
        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(draft: RecipeImportDraft()))
        let empty = RecipeTransferData(exportedAt: .now, ingredients: [], recipes: [])
        model.rawText = try #require(RecipeTransferMarker.line(for: empty))

        await model.extract(inventory: [], collections: [])

        #expect(model.phase == .failed(.nothingRecognised))
    }

    @Test func textCarriesExactPayload_MarkerPresent_IsTrue() {
        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(draft: RecipeImportDraft()))

        model.rawText = "Olive Oil 100%"
        #expect(!model.textCarriesExactPayload)

        model.rawText = RecipeTextExporter.clipboardText(for: fixture.populatedRecipe())
        #expect(model.textCarriesExactPayload)
    }

    @Test func returnToInput_AfterReadingAPayload_ForgetsIt() async throws {
        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(draft: RecipeImportDraft()))
        model.rawText = RecipeTextExporter.clipboardText(for: fixture.populatedRecipe())
        await model.extract(inventory: [], collections: [])

        model.returnToInput()

        #expect(model.phase == .input)
        #expect(model.transferPlan == nil)
    }

    // MARK: - Bare payload JSON

    /// The share sheet's own Copy puts the file on the pasteboard, and because
    /// the type conforms to `public.json` — and so to `public.text` — pasting it
    /// yields the raw JSON with no marker around it. Refusing that would mean
    /// the app writing something it then can't read back.
    @Test func scan_BarePayloadJSON_IsRecognised() throws {
        let built = fixture.payload([fixture.populatedRecipe()])
        let json = try #require(String(data: try RecipeTransferCoding.encoder.encode(built), encoding: .utf8))

        #expect(RecipeTransferDecoder.scan(text: json) == .payload(built))
    }

    @Test func scan_BarePayloadJSONWithSurroundingWhitespace_IsStillRecognised() throws {
        let built = fixture.payload([fixture.populatedRecipe()])
        let json = try #require(String(data: try RecipeTransferCoding.encoder.encode(built), encoding: .utf8))

        #expect(RecipeTransferDecoder.scan(text: "\n\n  \(json)  \n") == .payload(built))
    }

    @Test func scan_BareJSONFromANewerVersion_IsRejected() throws {
        var built = fixture.payload([fixture.populatedRecipe()])
        built.version = RecipeTransferData.currentVersion + 1
        let json = try #require(String(data: try RecipeTransferCoding.encoder.encode(built), encoding: .utf8))

        #expect(RecipeTransferDecoder.scan(text: json) == .rejected(
            .unsupportedVersion(found: RecipeTransferData.currentVersion + 1, supported: RecipeTransferData.currentVersion)
        ))
    }

    @Test func scan_UnrelatedJSON_FallsThroughToTheTextPath() {
        #expect(RecipeTransferDecoder.scan(text: #"{"hello":"world"}"#) == RecipeTransferScan.none)
    }

    @Test func scan_OrdinaryRecipeText_IsNotMistakenForJSON() {
        #expect(RecipeTransferDecoder.scan(text: "Olive Oil 55%\nCoconut Oil 30%") == RecipeTransferScan.none)
    }

    /// Text carrying both readable recipe and a marker is still read from the
    /// marker: it is the authority, and the JSON attempt never runs.
    @Test func scan_MarkerBearingText_StillPrefersTheMarker() throws {
        let recipe = fixture.populatedRecipe()
        fixture.context.processPendingChanges()

        let outcome = RecipeTransferDecoder.scan(text: RecipeTextExporter.clipboardText(for: recipe))

        guard case .payload(let decoded) = outcome else {
            Issue.record("Expected the marker to be read, got \(outcome)")
            return
        }
        #expect(decoded.recipes.first?.name == recipe.name)
    }

    @Test func extract_BarePayloadJSON_NeverCallsTheExtractor() async throws {
        let extractor = StubRecipeExtractor(error: .modelUnavailable("should not be reached"))
        let model = RecipeImportViewModel(extractor: extractor)
        let built = fixture.payload([fixture.populatedRecipe()])
        model.rawText = try #require(String(data: try RecipeTransferCoding.encoder.encode(built), encoding: .utf8))

        await model.extract(inventory: [], collections: [])

        #expect(model.phase == .exactReview)
        #expect(extractor.recorder.lastText == nil)
    }

}
