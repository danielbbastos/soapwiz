import Foundation

/// What opened the recipe list's import sheet. The two ways in share one sheet
/// so only ever one is up: the FAB, which starts on the input screen, and a file
/// handed in from another app, which skips straight to the exact-import review.
enum RecipeImportRequest: Identifiable {
    case manual
    case file(RecipeFileImport)

    var id: String {
        switch self {
        case .manual: "manual"
        case .file(let request): request.id.uuidString
        }
    }

    var fileURL: URL? {
        switch self {
        case .manual: nil
        case .file(let request): request.url
        }
    }
}
