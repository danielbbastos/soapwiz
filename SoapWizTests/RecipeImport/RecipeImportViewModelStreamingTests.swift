import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("RecipeImportViewModel streaming", .serialized)
@MainActor
struct RecipeImportViewModelStreamingTests: RecipeImportTestHelpers {

    @Test func extract_Streaming_FeedsEachSnapshotToStreamingDraft() async throws {
        let (container, context) = try makeContext()
        _ = container
        let inventory = makeInventory(in: context)

        let stub = StreamingStubExtractor(partials: Self.progressSnapshots, final: Self.progressFull)
        let model = RecipeImportViewModel(extractor: stub)
        var seen: [RecipeImportDraft] = []
        stub.afterPartial = {
            if let draft = model.streamingDraft { seen.append(draft) }
        }

        model.rawText = "Olive Oil 70%\nCoconut Oil 30%"
        await model.extract(inventory: inventory)

        #expect(seen == Self.progressSnapshots)
        #expect(model.phase == .review)
        // Cleared once the reconciled rows take over the screen.
        #expect(model.streamingDraft == nil)
    }

    @Test func extractionStatus_AdvancesAsTheDraftFillsIn() async throws {
        let stub = StreamingStubExtractor(partials: Self.progressSnapshots, final: Self.progressFull)
        let model = RecipeImportViewModel(extractor: stub)
        var statuses: [String] = []
        stub.afterPartial = { statuses.append(model.extractionStatus) }

        model.rawText = "recipe"
        await model.extract(inventory: [])

        #expect(statuses == [
            "Reading the text\u{2026}",
            "Finding ingredients\u{2026}",
            "Checking amounts\u{2026}"
        ])
    }

    @Test func extractionStatus_BeforeAnySnapshot_ReadsTheText() {
        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(draft: .mock()))
        #expect(model.extractionStatus == "Reading the text\u{2026}")
    }

    @Test func extract_StreamFailsMidway_SurfacesTheErrorAndClearsTheDraft() async throws {
        let partial = RecipeImportDraft(
            name: "Castile Bar",
            oils: [ImportedIngredient(name: "Olive Oil", amount: 70, unit: nil)]
        )
        let extractor = StreamingFailingExtractor(partials: [partial], error: .failed("boom"))
        let model = RecipeImportViewModel(extractor: extractor)
        model.rawText = "Olive Oil 70%"
        await model.extract(inventory: [])

        #expect(model.phase == .failed(.failed("boom")))
        #expect(model.streamingDraft == nil)
    }

    // MARK: - Fixtures

    /// A recipe as it fills in: a bare name, then oils, then the finished draft
    /// with lye settings — one instance so the two streaming tests compare the
    /// same values the stub emitted.
    private static let progressFull = RecipeImportDraft.mock()
    private static let progressSnapshots: [RecipeImportDraft] = [
        RecipeImportDraft(name: "Castile Bar"),
        RecipeImportDraft(name: "Castile Bar", oils: [ImportedIngredient(name: "Olive Oil", amount: 70, unit: nil)]),
        progressFull
    ]
}
