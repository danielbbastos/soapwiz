import SwiftUI

/// The cart in Inventory's toolbar. Pro opens the shopping list; anyone else
/// is shown what Pro adds. The tour's sandbox counts as unlimited, as for the
/// other Pro features.
struct ShoppingListToolbarButton: View {
    @FreeTierGateEnvironment private var freeTier

    @Binding var isPresented: Bool

    var body: some View {
        Button("Shopping list", systemImage: "cart") {
            freeTier.ifAvailable(.shoppingList) { isPresented = true }
        }
    }
}

extension View {
    func shoppingListSheet(
        isPresented: Binding<Bool>,
        ingredients: [Ingredient],
        purchases: [IngredientPurchase],
        tracksInventory: Bool
    ) -> some View {
        sheet(isPresented: isPresented) {
            ShoppingListView(ingredients: ingredients, purchases: purchases, tracksInventory: tracksInventory)
        }
    }
}
