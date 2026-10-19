import SwiftUI

/// Entering the mode, and leaving it with or without sharing or deleting.
///
/// Laid out to match the Inventory tab: the bulk action leading, Select and
/// Done trailing. Two lists that both offer a selection mode should not put
/// the way out of it in different corners.
///
/// How many recipes are selected is shown in the navigation title rather
/// than on the button, since a compact toolbar draws the button as its icon
/// alone and any count in its label would never be seen.
struct RecipeSelectionToolbar: ToolbarContent {
    let model: RecipeListViewModel
    let recipes: [Recipe]

    var body: some ToolbarContent {
        if model.isSelecting {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    // Every selected recipe, not just the ones on screen. A
                    // collection chip tapped mid-selection changes what is
                    // displayed, and exporting only the survivors would send
                    // fewer recipes than the title says are selected.
                    model.exportSelection(from: recipes)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel(model.exportButtonTitle)
                .disabled(!model.hasSelection)

                Button(role: .destructive) {
                    model.requestDeleteSelection(from: recipes)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .accessibilityLabel(model.deleteButtonTitle)
                .disabled(!model.hasSelection)
            }
        }
        if !recipes.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button(model.isSelecting ? "Done" : "Select") {
                    if model.isSelecting {
                        model.endSelecting()
                    } else {
                        model.beginSelecting()
                    }
                }
            }
        }
    }
}
