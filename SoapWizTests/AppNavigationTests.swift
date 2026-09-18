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
}
