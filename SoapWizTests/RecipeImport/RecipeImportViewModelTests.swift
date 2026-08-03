import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("RecipeImportViewModel", .serialized)
@MainActor
struct RecipeImportViewModelTests: RecipeImportTestHelpers {

    // MARK: - Input state

    @Test func canExtract_EmptyText_IsFalse() {
        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(draft: .mock()))
        #expect(!model.canExtract)
        model.rawText = "   \n  "
        #expect(!model.canExtract)
    }

    @Test func canExtract_WithText_IsTrue() {
        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(draft: .mock()))
        model.rawText = "Olive Oil 70%"
        #expect(model.canExtract)
    }

    // MARK: - Happy path

    @Test func extract_MatchingInventory_ReachesReviewFullyResolved() async throws {
        let (container, context) = try makeContext()
        _ = container
        let inventory = makeInventory(in: context)

        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(draft: .mock()))
        model.rawText = "Olive Oil 70%\nCoconut Oil 30%"
        await model.extract(inventory: inventory)

        #expect(model.phase == .review)
        #expect(model.rows.count == 2)
        #expect(model.unresolvedCount == 0)
        #expect(model.canConfirm)
        #expect(model.confirmBlocker == nil)
        #expect(model.prepared != nil)
    }

    @Test func extract_SanitizesBeforeSending() async throws {
        let (container, context) = try makeContext()
        _ = container
        let inventory = makeInventory(in: context)

        let stub = StubRecipeExtractor(draft: .mock())
        let model = RecipeImportViewModel(extractor: stub)
        model.rawText = "<p>Olive Oil 70%</p><p>Coconut Oil 30%</p>"
        await model.extract(inventory: inventory)

        let sent = try #require(stub.recorder.lastText)
        #expect(!sent.text.contains("<p>"))
        #expect(sent.text.contains("Olive Oil 70%"))
    }

    // MARK: - Unresolved rows

    @Test func extract_UnknownOil_BlocksConfirmUntilResolved() async throws {
        let (container, context) = try makeContext()
        _ = container
        let inventory = makeInventory(in: context)

        let draft = RecipeImportDraft.mock(oils: [
            ImportedIngredient(name: "Olive Oil", amount: 70, unit: nil),
            ImportedIngredient(name: "Babassu Oil", amount: 30, unit: nil)
        ])
        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(draft: draft))
        model.rawText = "recipe"
        await model.extract(inventory: inventory)

        #expect(model.unresolvedCount == 1)
        #expect(!model.canConfirm)
        #expect(model.confirmBlocker == "One ingredient still needs to be created or skipped.")
        #expect(model.prepared == nil)

        let unresolved = try #require(model.rows.first { !$0.isResolved })
        model.skip(unresolved.id)

        #expect(model.canConfirm)
        #expect(model.prepared != nil)
    }

    @Test func confirmBlocker_SeveralUnresolved_CountsThem() async throws {
        let draft = RecipeImportDraft.mock(oils: [
            ImportedIngredient(name: "Babassu Oil", amount: 50, unit: nil),
            ImportedIngredient(name: "Kokum Butter", amount: 50, unit: nil)
        ])
        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(draft: draft))
        model.rawText = "recipe"
        await model.extract(inventory: [])

        #expect(model.confirmBlocker == "2 ingredients still need to be created or skipped.")
    }

    @Test func canConfirm_EverythingSkipped_StaysBlocked() async throws {
        let draft = RecipeImportDraft.mock(oils: [ImportedIngredient(name: "Babassu Oil", amount: 100, unit: nil)])
        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(draft: draft))
        model.rawText = "recipe"
        await model.extract(inventory: [])

        model.skip(try #require(model.rows.first).id)

        #expect(model.unresolvedCount == 0)
        #expect(!model.canConfirm)
        #expect(model.confirmBlocker == "A recipe needs at least one oil from your inventory.")
    }

    @Test func unskip_ReturnsTheRowToUnresolved() async throws {
        let draft = RecipeImportDraft.mock(oils: [ImportedIngredient(name: "Babassu Oil", amount: 100, unit: nil)])
        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(draft: draft))
        model.rawText = "recipe"
        await model.extract(inventory: [])

        let rowID = try #require(model.rows.first).id
        model.skip(rowID)
        model.unskip(rowID)

        #expect(model.unresolvedCount == 1)
    }

    @Test func refreshResolutions_AfterCreatingTheIngredient_ResolvesTheRow() async throws {
        let (container, context) = try makeContext()
        _ = container
        var inventory = makeInventory(in: context)

        let draft = RecipeImportDraft.mock(oils: [ImportedIngredient(name: "Babassu Oil", amount: 100, unit: nil)])
        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(draft: draft))
        model.rawText = "recipe"
        await model.extract(inventory: inventory)
        #expect(model.unresolvedCount == 1)

        inventory.append(makeOil(name: "Babassu Oil", sap: 0.175, category: nil, context: context))
        model.refreshResolutions(inventory: inventory)

        #expect(model.unresolvedCount == 0)
        #expect(model.canConfirm)
    }

    // MARK: - Failures

    @Test func extract_NothingRecognised_Fails() async throws {
        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(error: .nothingRecognised))
        model.rawText = "Olive Oil 70%"
        await model.extract(inventory: [])

        #expect(model.phase == .failed(.nothingRecognised))
        #expect(model.rows.isEmpty)
        #expect(model.prepared == nil)
    }

    @Test func extract_TextSanitizesToNothing_FailsWithoutCallingTheModel() async throws {
        let stub = StubRecipeExtractor(draft: .mock())
        let model = RecipeImportViewModel(extractor: stub)
        model.rawText = "Share this:\nLeave a comment"
        await model.extract(inventory: [])

        #expect(model.phase == .failed(.nothingRecognised))
        #expect(stub.recorder.lastText == nil)
    }

    @Test func extract_NoExtractorAvailable_ReportsTheModelUnavailable() async throws {
        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(error: .modelUnavailable("no")))
        model.rawText = "Olive Oil 70%"
        await model.extract(inventory: [])

        #expect(model.phase == .failed(.modelUnavailable("no")))
    }

    @Test func extract_Failure_WritesNothingToTheStore() async throws {
        let (container, context) = try makeContext()
        _ = container
        let inventory = makeInventory(in: context)

        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(error: .failed("boom")))
        model.rawText = "Olive Oil 70%"
        await model.extract(inventory: inventory)

        #expect(try context.fetch(FetchDescriptor<Recipe>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<RecipeIngredient>()).isEmpty)
    }

    @Test func returnToInput_AfterAFailure_GoesBackToTheTextField() async throws {
        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(error: .inputTooLong))
        model.rawText = "Olive Oil 70%"
        await model.extract(inventory: [])
        #expect(model.phase == .failed(.inputTooLong))

        model.returnToInput()
        #expect(model.phase == .input)
        #expect(model.rawText == "Olive Oil 70%")
    }

    // MARK: - Context-window retry

    @Test func extract_TooLong_RetriesOnceWithLessText() async throws {
        let (container, context) = try makeContext()
        _ = container
        let inventory = makeInventory(in: context)

        let extractor = RetryingStubExtractor(firstError: .inputTooLong, then: .mock())
        let model = RecipeImportViewModel(extractor: extractor)
        model.rawText = Self.longRecipe
        await model.extract(inventory: inventory)

        #expect(extractor.callCount == 2)
        #expect(extractor.budgets[1] < extractor.budgets[0])
        #expect(model.phase == .review)
    }

    @Test func extract_TooLongTwice_SurfacesTheError() async throws {
        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(error: .inputTooLong))
        model.rawText = Self.longRecipe
        await model.extract(inventory: [])

        #expect(model.phase == .failed(.inputTooLong))
    }

    @Test func extract_OtherErrors_AreNotRetried() async throws {
        let extractor = RetryingStubExtractor(firstError: .failed("boom"), then: .mock())
        let model = RecipeImportViewModel(extractor: extractor)
        model.rawText = "Olive Oil 70%"
        await model.extract(inventory: [])

        #expect(extractor.callCount == 1)
        #expect(model.phase == .failed(.failed("boom")))
    }

    @Test func extract_RecordsWhatTheSanitizerDid() async throws {
        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(draft: .mock()))
        model.rawText = Self.longRecipe
        await model.extract(inventory: [])

        let sanitized = try #require(model.sanitized)
        #expect(sanitized.originalLength == Self.longRecipe.count)
        #expect(sanitized.wasTrimmed)
    }

    // MARK: - Fixtures

    private static let longRecipe: String = {
        let filler = Array(repeating: "This is another paragraph about the history of soap.", count: 300)
        return (filler + ["Olive Oil 700 g", "Coconut Oil 300 g", "Superfat 5%"]).joined(separator: "\n")
    }()
}
