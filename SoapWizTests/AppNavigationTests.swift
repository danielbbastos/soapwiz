import Testing
import SwiftUI
import SwiftData
@testable import SoapWiz

@Suite("AppNavigation")
@MainActor
struct AppNavigationTests {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([Batch.self, BatchLineItem.self, Recipe.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    private func makeBatch(_ ctx: ModelContext, name: String = "Test Soap") -> Batch {
        let batch = Batch(recipe: nil, recipeName: name, batchCount: 1)
        ctx.insert(batch)
        return batch
    }

    @Test func initialState_InventoryTabAndEmptyHistoryPath() {
        let sut = AppNavigation()

        #expect(sut.selectedTab == .inventory)
        #expect(sut.historyPath.isEmpty)
    }

    @Test func showBatch_SelectsHistoryTab() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let sut = AppNavigation()
        sut.selectedTab = .recipes

        sut.showBatch(makeBatch(ctx))

        #expect(sut.selectedTab == .history)
    }

    @Test func showBatch_PathContainsOnlyTheBatch() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let sut = AppNavigation()

        sut.showBatch(makeBatch(ctx))

        #expect(sut.historyPath.count == 1)
    }

    @Test func showBatch_DeepHistoryStack_ReplacesPathInsteadOfStacking() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let sut = AppNavigation()
        sut.historyPath.append(makeBatch(ctx, name: "Old Soap"))
        sut.historyPath.append(makeBatch(ctx, name: "Older Soap"))

        sut.showBatch(makeBatch(ctx))

        #expect(sut.historyPath.count == 1)
    }

    @Test func openRecipeFile_SelectsRecipesTabAndStoresRequest() throws {
        let sut = AppNavigation()
        let url = URL(fileURLWithPath: "/tmp/shared.soapwizrecipe")

        sut.openRecipeFile(url)

        #expect(sut.selectedTab == .recipes)
        let request = try #require(sut.pendingRecipeFileImport)
        #expect(request.url == url)
    }

    @Test func openRecipeFile_SameFileTwice_ProducesDistinctRequests() {
        let sut = AppNavigation()
        let url = URL(fileURLWithPath: "/tmp/shared.soapwizrecipe")

        sut.openRecipeFile(url)
        let first = sut.pendingRecipeFileImport

        sut.openRecipeFile(url)
        let second = sut.pendingRecipeFileImport

        // Distinct ids so an `onChange` observer fires again on the second open,
        // even though the URL is unchanged.
        #expect(first != second)
        #expect(first?.url == second?.url)
    }

    // MARK: - A file opened while the recipe form covers the screen (SW-89)

    @Test func takePendingRecipeFileImport_NoFormOpen_HandsTheFileOutOnce() throws {
        let sut = AppNavigation()
        sut.openRecipeFile(URL(fileURLWithPath: "/tmp/shared.soapwizrecipe"))
        let opened = try #require(sut.pendingRecipeFileImport)

        #expect(sut.takePendingRecipeFileImport() == opened)
        #expect(sut.pendingRecipeFileImport == nil)
        #expect(sut.takePendingRecipeFileImport() == nil)
    }

    @Test func takePendingRecipeFileImport_FormOpen_HoldsTheFileUntilItCloses() throws {
        let sut = AppNavigation()
        sut.recipeFormRequest = .new()
        sut.openRecipeFile(URL(fileURLWithPath: "/tmp/shared.soapwizrecipe"))
        let opened = try #require(sut.pendingRecipeFileImport)

        #expect(sut.takePendingRecipeFileImport() == nil)
        #expect(sut.pendingRecipeFileImport == opened)

        sut.recipeFormRequest = nil
        sut.recipeFormDidClose()

        #expect(sut.takePendingRecipeFileImport() == opened)
    }

    /// The request clears as the cover starts to leave; the file must wait for
    /// the cover to be gone, or its import review goes up mid-dismissal.
    @Test func takePendingRecipeFileImport_FormStillClosing_HoldsTheFile() throws {
        let sut = AppNavigation()
        sut.recipeFormRequest = .new()
        sut.openRecipeFile(URL(fileURLWithPath: "/tmp/shared.soapwizrecipe"))
        let opened = try #require(sut.pendingRecipeFileImport)

        sut.recipeFormRequest = nil

        #expect(sut.isRecipeFormOnScreen)
        #expect(sut.takePendingRecipeFileImport() == nil)

        sut.recipeFormDidClose()

        #expect(sut.isRecipeFormOnScreen == false)
        #expect(sut.takePendingRecipeFileImport() == opened)
    }

    @Test func discardRecipeForm_ClearsTheFormAtOnce() {
        let sut = AppNavigation()
        sut.recipeFormRequest = .new()

        sut.discardRecipeForm()

        #expect(sut.recipeFormRequest == nil)
        #expect(sut.isRecipeFormOnScreen == false)
    }

    /// Kept editing, then opened again: the file waiting is the newest open.
    @Test func takePendingRecipeFileImport_OpenedAgainWhileHeld_HandsOutTheNewestOpen() throws {
        let sut = AppNavigation()
        sut.recipeFormRequest = .new()
        let url = URL(fileURLWithPath: "/tmp/shared.soapwizrecipe")
        sut.openRecipeFile(url)
        sut.openRecipeFile(url)
        let newest = try #require(sut.pendingRecipeFileImport)

        sut.recipeFormRequest = nil
        sut.recipeFormDidClose()

        #expect(sut.takePendingRecipeFileImport() == newest)
    }

    @Test func recipeFormDidClose_CountsEachClosing() {
        let sut = AppNavigation()

        sut.recipeFormDidClose()
        sut.recipeFormDidClose()

        #expect(sut.recipeFormClosings == 2)
    }
}
