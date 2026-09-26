import Foundation

/// Why the recipe form is asking before it throws away unsaved changes.
enum RecipeFormCloseReason: Equatable {
    case cancel
    /// A recipe file opened from another app while the form covered the screen.
    /// Asked straight away, so the user can see the file arrived; left alone,
    /// the file opens once the form closes (SW-89).
    case fileImport(URL)

    var title: String {
        switch self {
        case .cancel:
            "Discard changes?"
        case .fileImport(let url):
            "Import “\(url.deletingPathExtension().lastPathComponent)”?"
        }
    }

    var message: String {
        switch self {
        case .cancel:
            "This recipe has changes that haven't been saved."
        case .fileImport:
            "This recipe has changes that haven't been saved. Discard them to open the file now, "
                + "or keep editing and it opens when you're done."
        }
    }

    var discardTitle: String {
        switch self {
        case .cancel: "Discard"
        case .fileImport: "Discard and Import"
        }
    }
}
