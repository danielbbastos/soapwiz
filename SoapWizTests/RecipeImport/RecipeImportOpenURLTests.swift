import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The open-from-another-app path: a `.soapwizrecipe` file on disk, opened
/// through the same `openFile` the in-app picker uses, lands on the exact
/// review and imports the sender's recipe intact.
@Suite("RecipeImport open URL", .serialized)
@MainActor
struct RecipeImportOpenURLTests {

    private func writeTempFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("soapwizrecipe")
        try data.write(to: url)
        return url
    }

    @Test func openFile_ExportedPayload_ImportsTheSenderRecipe() throws {
        let source = try RecipeTransferFixture()
        let recipe = source.populatedRecipe(named: "Shared Bar")
        source.context.processPendingChanges()
        let data = try RecipeTransferEncoder.fileData(for: [recipe])
        let url = try writeTempFile(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let destination = try RecipeTransferFixture()
        let model = RecipeImportViewModel()
        model.openFile(at: url, inventory: [], collections: [], recipes: [])

        #expect(model.phase == .exactReview)

        let categories = try destination.context.fetch(FetchDescriptor<IngredientCategory>())
        let imported = try #require(
            model.confirmExactImport(context: destination.context, categories: categories)
        )
        #expect(imported.count == 1)
        #expect(imported.first?.name == "Shared Bar")
    }

    @Test func openFile_NotASoapWizPayload_FailsWithoutCrashing() throws {
        let url = try writeTempFile(Data("this is not a recipe".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        let model = RecipeImportViewModel()
        model.openFile(at: url, inventory: [], collections: [], recipes: [])

        let didFail: Bool = if case .failed = model.phase { true } else { false }
        #expect(didFail)
    }
}
