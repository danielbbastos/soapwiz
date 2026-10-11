import SwiftUI
import SwiftData

/// The base-ingredient rows of the recipe form: adding, removing and editing
/// them, and the amount precision shared with the other ingredient sections.
extension RecipeFormViewModel {
    /// Fraction digits an oil amount field shows. The field and the unchanged
    /// check in `userEdited` both read this, so they can't drift apart.
    static let oilAmountFractionDigits = 1

    /// Fraction digits a fragrance or additive amount field shows.
    static let extraAmountFractionDigits = 3

    func addOil(_ ingredient: Ingredient) {
        guard !oilDrafts.contains(where: {
            $0.ingredient.persistentModelID == ingredient.persistentModelID
        }) else { return }
        oilDrafts.append(OilIngredientDraft(ingredient: ingredient))
        if weightUnitIsPercentage { redistributePercentages() }
    }

    func removeOil(at offsets: IndexSet) {
        oilDrafts.remove(atOffsets: offsets)
        if weightUnitIsPercentage { redistributePercentages() }
    }

    /// A commit from an oil amount field. The field writes its parsed value back
    /// every time editing ends, changed or not, so an amount equal to the stored
    /// one at the displayed precision is ignored: focusing a row and leaving it
    /// must not lock it or redistribute the others.
    func userEdited(id: UUID, amount: Double) {
        guard let draft = oilDrafts.first(where: { $0.id == id }),
              !draft.amount.matches(amount, fractionDigits: Self.oilAmountFractionDigits) else { return }
        setOilAmount(id: id, amount: amount)
    }

    /// Assigns an oil amount unconditionally, locking the row in percentage
    /// mode and redistributing the rest. Import uses this directly because a
    /// row whose amount happens to equal its current share must still lock.
    func setOilAmount(id: UUID, amount: Double) {
        guard let idx = oilDrafts.firstIndex(where: { $0.id == id }) else { return }
        oilDrafts[idx].amount = amount
        if weightUnitIsPercentage {
            oilDrafts[idx].isLocked = true
            redistributePercentages()
        }
    }
}
