import Testing
import Foundation
import UniformTypeIdentifiers
@testable import SoapWiz

/// The `.soapwizrecipe` type being properly declared, rather than merely
/// referenced.
///
/// The declaration lives in `Config/SoapWiz-Info.plist` and reaches the app
/// through the `INFOPLIST_FILE` build setting, merged with the keys
/// `GENERATE_INFOPLIST_FILE` produces. That is a quiet piece of wiring: drop the
/// setting and everything still compiles, every other test still passes, and the
/// only symptom is a share sheet that calls a recipe an anonymous document and a
/// file picker that won't open one.
@Suite
struct RecipeTransferTypeTests {

    /// Deliberately not asserted through `isDeclared` or `isDynamic`: a
    /// `UTType(exportedAs:)` reports itself declared and non-dynamic whether or
    /// not anything actually declares it, so those two read as a guard while
    /// testing nothing. Every assertion below was confirmed to fail with the
    /// `INFOPLIST_FILE` setting removed.
    @Test func soapWizRecipe_Always_OwnsTheExtensionExportWrites() {
        #expect(UTType.soapWizRecipe.preferredFilenameExtension == RecipeTransferExport.fileExtension)
    }

    /// What lets a recipe file be previewed as the JSON it is, rather than
    /// treated as an opaque blob.
    @Test func soapWizRecipe_Always_ConformsToJSON() {
        #expect(UTType.soapWizRecipe.conforms(to: .json))
    }

    /// The reverse lookup the file picker performs when the user taps a file.
    @Test func typeForFileExtension_OurExtension_ResolvesToOurType() {
        let resolved = UTType(filenameExtension: RecipeTransferExport.fileExtension)

        #expect(resolved == .soapWizRecipe)
    }

    @Test func soapWizRecipe_Always_HasADescriptionToShowInTheShareSheet() throws {
        let description = try #require(UTType.soapWizRecipe.localizedDescription)

        #expect(!description.isEmpty)
    }
}
