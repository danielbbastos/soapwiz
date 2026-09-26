import SwiftUI

/// What the recipe form is opened for. On iPhone each case is pushed onto the
/// stack it was opened from, as its `route`; on iPad the request is set on
/// `AppNavigation.recipeFormRequest` and `ContentView` covers the screen with
/// the form, above the tabs (SW-89).
enum RecipeFormRequest: Identifiable {
    case new(UUID = UUID())
    case seeded(RecipeSeed)
    case imported(PreparedRecipeImport)
    case edit(Recipe, id: UUID = UUID())

    var id: UUID {
        switch self {
        case .new(let id): id
        case .seeded(let seed): seed.id
        case .imported(let prepared): prepared.id
        case .edit(_, let id): id
        }
    }

    /// The value pushed for this request where the form is a push. Unchanged
    /// from before SW-89, so the existing destinations still route it.
    var route: AnyHashable {
        switch self {
        case .new: AnyHashable(true)
        case .seeded(let seed): AnyHashable(seed)
        case .imported(let prepared): AnyHashable(prepared)
        case .edit(let recipe, _): AnyHashable(RecipeEditRoute(recipe: recipe))
        }
    }

    /// Whether the recipe form opens full screen over the tabs rather than being
    /// pushed. On iPad a pushed form sat under the floating tab bar, which let a
    /// tab be switched mid-edit, and the wide layouts rebuild a tab's navigation
    /// when the window width changes. A cover owned by any screen inside a tab
    /// closes with that screen, taking an unsaved recipe with it, so the one
    /// cover lives above the tabs. The device rather than the size class, so
    /// the form stays full screen in a narrow multitasking window too.
    static var opensFullScreen: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
}
