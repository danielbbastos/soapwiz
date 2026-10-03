import SwiftUI

/// One Inventory row with its tap, swipe and selection handling.
///
/// A view of its own rather than a function of the list, so that a refresh of
/// the list only compares three references per row: the list refreshes on every
/// save to the store, and an iCloud import saves many times a second (SW-219).
/// Each row then redraws only when something it reads has changed.
///
/// A `Button` rather than a `NavigationLink`, purely to drop the disclosure
/// chevron: a link used as a row's root always draws one and there is no
/// modifier to suppress it. The push is the same, just issued by hand. This is
/// what the recipe list already does.
///
/// While selecting, the row is its bare content instead: the list is then
/// handling taps itself to build the selection, and a button in the way would
/// take them.
struct IngredientListRow: View {
    let ingredient: Ingredient
    let model: IngredientListViewModel
    let navigation: ListDetailNavigation<Ingredient>

    var body: some View {
        let content = IngredientRowView(ingredient: ingredient, model: model)
        if model.editMode == .active {
            content
                .listRowBackground(Color.paperRaised)
                .listRowSeparatorTint(Color.rule)
        } else {
            Button {
                navigation.show(ingredient)
            } label: {
                // A `Button` is hit-tested over its drawn content only, so
                // without this the row's padding and the gap left of the star
                // are dead to touch — a `NavigationLink` row was tappable
                // across the whole cell.
                content
                    .contentShape(Rectangle())
            }
            // Keeps the row from taking on button tinting; the star inside stays
            // tappable because it is `.borderless`.
            .buttonStyle(.plain)
            // A library row offers Hide instead: deleting it would only bring a
            // pristine copy back on the next launch, so the destructive styling
            // would be promising something the installer immediately undoes.
            .swipeActions(edge: .trailing) {
                if ingredient.isLibraryInstalled {
                    Button("Hide") {
                        model.hide(ingredient)
                    }
                    .tint(.orange)
                } else {
                    Button("Delete", role: .destructive) {
                        model.delete(ingredient)
                    }
                }
            }
            .ledgerListDetailRow(isSelected: navigation.isOpenBeside(ingredient))
        }
    }
}
