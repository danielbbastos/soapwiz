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

    @Test func extractionStatus_FastRead_NeverShowsAWaitHint() async {
        let stub = StreamingStubExtractor(partials: Self.progressSnapshots, final: Self.progressFull)
        let model = RecipeImportViewModel(extractor: stub)
        var statuses: [String] = []
        stub.afterPartial = { statuses.append(model.extractionStatus) }

        model.rawText = "recipe"
        await model.extract(inventory: [])

        #expect(!statuses.isEmpty)
        #expect(statuses.allSatisfy { !RecipeImportWaitHints.lines.contains($0) })
    }

    @Test func extractionStatus_SlowStart_CyclesThroughTheWaitHintsAndWraps() async {
        let hints = RecipeImportWaitHints.lines
        let probe = WaitHintProbe(pauses: hints.count + 1)
        let stub = StreamingStubExtractor(partials: Self.progressSnapshots, final: Self.progressFull)
        let model = RecipeImportViewModel(extractor: stub, waitHints: probe.waitHints)
        probe.model = model
        stub.beforeFirstPartial = { await probe.waitUntilFinished() }

        model.rawText = "recipe"
        await model.extract(inventory: [])

        #expect(probe.statuses == ["Reading the text\u{2026}"] + hints + [hints[0]])
    }

    @Test func extractionStatus_SlowStartThenIngredients_GivesWayToTheStreamingSteps() async {
        let probe = WaitHintProbe(pauses: 1)
        let stub = StreamingStubExtractor(partials: Self.progressSnapshots, final: Self.progressFull)
        let model = RecipeImportViewModel(extractor: stub, waitHints: probe.waitHints)
        probe.model = model
        stub.beforeFirstPartial = { await probe.waitUntilFinished() }
        var statuses: [String] = []
        stub.afterPartial = { statuses.append(model.extractionStatus) }

        model.rawText = "recipe"
        await model.extract(inventory: [])

        // The name-only snapshot has no ingredient yet, so the hint stays.
        #expect(statuses == [
            RecipeImportWaitHints.lines[0],
            "Finding ingredients\u{2026}",
            "Checking amounts\u{2026}"
        ])
        #expect(model.phase == .review)
        #expect(model.extractionStatus == "Reading the text\u{2026}")
    }

    @Test func extract_SlowStartThenFailure_ClearsTheWaitHint() async {
        let probe = WaitHintProbe(pauses: 1)
        var extractor = StreamingFailingExtractor(partials: [], error: .failed("boom"))
        extractor.beforeFirstPartial = { await probe.waitUntilFinished() }
        let model = RecipeImportViewModel(extractor: extractor, waitHints: probe.waitHints)
        probe.model = model

        model.rawText = "recipe"
        await model.extract(inventory: [])

        #expect(model.phase == .failed(.failed("boom")))
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

/// Stands in for the clock between wait hints, so a test steps through them
/// without waiting seconds. Records the status line at every pause; after
/// `pauses` of them it lets the extractor go on and holds until the read ends
/// and cancels it.
@MainActor
final class WaitHintProbe {
    weak var model: RecipeImportViewModel?
    private(set) var statuses: [String] = []
    private let pauses: Int
    private let finished: AsyncStream<Void>
    private let finish: AsyncStream<Void>.Continuation

    init(pauses: Int) {
        self.pauses = pauses
        (finished, finish) = AsyncStream.makeStream()
    }

    /// Wait hints that pause on this probe instead of a real clock.
    var waitHints: RecipeImportWaitHints {
        RecipeImportWaitHints(pause: { try await self.pause() })
    }

    func pause() async throws {
        statuses.append(model?.extractionStatus ?? "")
        guard statuses.count > pauses else { return }
        finish.yield()
        try await Task.sleep(for: .seconds(3600))
    }

    func waitUntilFinished() async {
        for await _ in finished { return }
    }
}
