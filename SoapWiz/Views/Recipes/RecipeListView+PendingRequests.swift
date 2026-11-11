import SwiftUI

/// Requests that arrive from elsewhere in the app and wait for the list to be
/// free to act on them.
extension RecipeListView {
    /// Opens the import review for a file handed in from another app. A sheet
    /// can't go up over the full-screen form, a detail sheet or the tour cover,
    /// so while one is open the file stays pending and this runs again once it
    /// has closed; either way its unsaved edits are left alone. Transient
    /// sheets are cleared first so the import isn't blocked by one already up.
    func startPendingFileImport() {
        guard let request = nav.takePendingRecipeFileImport(tourCoverOnScreen: tourLauncher.isCoverOnScreen) else { return }
        model.endSelecting()
        model.filingRecipe = nil
        model.exportFile = nil
        importRequest = .file(request)
    }

    /// Opens what Home's first-run screen asked for, under the same guard as a
    /// file import: not over the recipe form, a detail sheet or the tour cover.
    func startPendingLaunch() {
        guard let request = nav.takePendingRecipesLaunch(tourCoverOnScreen: tourLauncher.isCoverOnScreen) else { return }
        model.endSelecting()
        switch request.kind {
        case .importRecipe: openImport()
        case .starterLibrary: showingStarterRecipes = true
        }
    }
}
