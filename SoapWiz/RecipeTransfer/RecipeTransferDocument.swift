import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// The `.soapwizrecipe` document, declared in `Config/SoapWiz-Info.plist`.
    ///
    /// Conforms to `public.json` rather than `public.data`: the payload really is
    /// JSON, and saying so means anything that can preview JSON can show a
    /// recipe file rather than treating it as an opaque blob.
    ///
    /// Declaring it is also what makes the share sheet name the thing being
    /// shared — "SoapWiz Recipe · 3 KB" rather than an anonymous document.
    static let soapWizRecipe = UTType(exportedAs: "pt.daphnia.soapwiz.recipe")
}
