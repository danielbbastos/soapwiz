import Foundation

/// Adding and removing the recipe's product sizes. The first draft is always the
/// whole-batch default.
extension RecipeFormViewModel {
    func addProduct(defaultUnitSymbol: String) {
        productDrafts.append(RecipeProductDraft(unitSymbol: defaultUnitSymbol))
    }

    /// Removes a size and returns the id of the card before it. The first draft
    /// is the whole-batch default and cannot be removed, so nil is returned for
    /// it and for an unknown id.
    @discardableResult
    func removeProduct(id: UUID) -> UUID? {
        guard let index = productDrafts.firstIndex(where: { $0.id == id }), index > 0 else { return nil }
        productDrafts.remove(at: index)
        return productDrafts[index - 1].id
    }
}
