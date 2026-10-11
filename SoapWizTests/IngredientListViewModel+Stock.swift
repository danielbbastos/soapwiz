import Foundation
@testable import SoapWiz

extension IngredientListViewModel {
    /// Filters with stock read from the ingredients' own purchases, as the
    /// view's purchase fetch would supply it.
    func filtered(_ ingredients: [Ingredient]) -> [Ingredient] {
        filtered(ingredients, stock: StockLevels(ingredients.flatMap(\.purchases)))
    }
}
