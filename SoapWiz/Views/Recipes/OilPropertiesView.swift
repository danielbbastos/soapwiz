import SwiftUI

/// An oil's soap chemistry, pushed from the ingredient picker: SAP, the soap
/// qualities chart and the fatty acid breakdown. Purchases, usage and editing
/// stay on the ingredient's own screen, so picking oils can be informed without
/// leaving the picker.
struct OilPropertiesView: View {
    let ingredient: Ingredient

    var body: some View {
        List {
            IngredientChemistrySections(ingredient: ingredient, prefersColumns: false)
        }
        .readableWidth()
        .navigationTitle(ingredient.name)
        .navigationBarTitleDisplayMode(.inline)
        .honeyLedgerInlineTitle(ingredient.name)
        .ledgerBackground()
    }
}
