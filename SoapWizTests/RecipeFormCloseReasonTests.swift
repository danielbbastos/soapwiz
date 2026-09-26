import Testing
import Foundation
@testable import SoapWiz

/// What the recipe form says before discarding unsaved changes: for Cancel,
/// and for a recipe file that arrived while it covered the screen (SW-89).
@Suite("RecipeFormCloseReason")
struct RecipeFormCloseReasonTests {

    @Test func cancel_KeepsTheExistingWording() {
        let reason = RecipeFormCloseReason.cancel

        #expect(reason.title == "Discard changes?")
        #expect(reason.message == "This recipe has changes that haven't been saved.")
        #expect(reason.discardTitle == "Discard")
    }

    @Test func fileImport_NamesTheFileWithoutItsExtension() {
        let url = URL(fileURLWithPath: "/tmp/Inbox/4 SoapWiz Recipes.soapwizrecipe")

        #expect(RecipeFormCloseReason.fileImport(url).title == "Import “4 SoapWiz Recipes”?")
    }

    @Test func fileImport_OffersToDiscardAndImport() {
        let reason = RecipeFormCloseReason.fileImport(URL(fileURLWithPath: "/tmp/Castile.soapwizrecipe"))

        #expect(reason.discardTitle == "Discard and Import")
        #expect(reason.message.contains("Discard them to open the file now"))
        #expect(reason.message.contains("keep editing and it opens when you're done"))
    }
}
