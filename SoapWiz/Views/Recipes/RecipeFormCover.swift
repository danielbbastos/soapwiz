import SwiftUI

/// The recipe form for a full-screen request, in its own stack so the form's
/// title, Cancel and Save, and the pickers it pushes have a navigation bar to
/// live in. No `onSave`: the recipe list returns to its root before opening a
/// new recipe here, which is where the push's `onSave` returns the user, and
/// the recipe screen reloads on its own once its edit has closed.
///
/// A recipe file opened meanwhile is handed to the form, which offers to close
/// for it so the user sees the file arrived; the Recipes tab opens it once the
/// form is gone.
struct RecipeFormCover: View {
    let request: RecipeFormRequest

    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        let incomingFile = navigation.pendingRecipeFileImport
        NavigationStack {
            switch request {
            case .new:
                RecipeFormView(incomingFile: incomingFile)
            case .seeded(let seed):
                RecipeFormView(seed: seed, incomingFile: incomingFile)
            case .imported(let prepared):
                RecipeFormView(importDraft: prepared, incomingFile: incomingFile)
            case .edit(let recipe, _):
                RecipeFormView(recipe: recipe, incomingFile: incomingFile)
            }
        }
    }
}
