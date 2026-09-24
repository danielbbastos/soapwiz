import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// "Copy Recipe" is the one copy action: readable text, which the importer
/// reads back with `RecipeTextExportReader` rather than as an exact file.
@MainActor
@Suite
struct RecipeClipboardExportTests {

    private let fixture: RecipeTransferFixture

    init() throws {
        fixture = try RecipeTransferFixture()
    }

    @Test func text_Always_IsNotTakenForAPastedFile() {
        let readable = RecipeTextExporter.text(for: fixture.populatedRecipe())

        #expect(RecipeTransferDecoder.scan(text: readable) == RecipeTransferScan.none)
    }

    @Test func text_PopulatedRecipe_IsReadBackWithoutTheModel() throws {
        let recipe = fixture.populatedRecipe()

        let draft = try #require(RecipeTextExportReader.read(RecipeTextExporter.text(for: recipe)))

        #expect(draft.name == recipe.name)
    }
}
