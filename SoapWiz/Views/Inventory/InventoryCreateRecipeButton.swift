import SwiftUI

/// Shown while in select mode, floating above the tab bar (a `.bottomBar`
/// toolbar item would sit behind the TabView's tab bar).
struct InventoryCreateRecipeButton: View {
    @Environment(AppNavigation.self) private var nav

    let model: IngredientListViewModel
    let selected: [Ingredient]

    var body: some View {
        Button {
            model.editMode = .inactive
            model.selection.removeAll()
            nav.createRecipe(with: selected)
        } label: {
            Text("Create recipe with… (\(model.selection.count))")
                .font(.headline)
                .foregroundStyle(Color.ink)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.paperRaised, in: .capsule)
                .overlay(Capsule().strokeBorder(Color.ruleStrong, lineWidth: 1))
                .shadow(color: Color.shadow.opacity(0.18), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}
