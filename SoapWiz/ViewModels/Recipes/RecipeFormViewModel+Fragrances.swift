import SwiftUI
import SwiftData

/// The fragrance section of the recipe form: the recipe-wide unit, the rows
/// entered in it, and the rules that keep them consistent with each other and
/// with the recipe's fragrance load. Kept apart from the rest of the form
/// because the units interact — switching one re-expresses every row.
extension RecipeFormViewModel {
    var fragranceTargetPercentage: Double { fragrancePercentage }

    /// Recommended fragrance load shown beside the fragrance section header. For
    /// absolute mass units it is the target the entered weights should reach;
    /// for `% of fragrances` it is the resolved load the blend shares are scaled
    /// to, so it can never be exceeded. For the other percentage units
    /// (% of oils / batch / liquids) it isn't shown: the user is either already
    /// working in % of oils, or deliberately using a different base.
    var fragranceTarget: FragranceTarget? {
        guard !fragranceDrafts.isEmpty else { return nil }
        let totalOilBatchWeight = lyeCalculator.totalOilBatchWeight
        guard totalOilBatchWeight > 0 else { return nil }
        let targetInOilUnit = totalOilBatchWeight * fragranceTargetPercentage / 100

        if fragranceUnit == .percentOfFragrances {
            let amountText = targetInOilUnit.formatted(.number.precision(.fractionLength(0...2)))
            return FragranceTarget(
                text: "\(amountText) \(displayWeightUnit) (\(formatPercentage(fragranceTargetPercentage))%)",
                percentage: fragranceTargetPercentage,
                isOverTarget: false
            )
        }
        let unit = fragranceUnit.rawValue
        guard MassUnitConverter.isMass(unit) else { return nil }
        let target = MassUnitConverter.convert(targetInOilUnit, from: displayWeightUnit, to: unit) ?? targetInOilUnit
        let amountText = target.formatted(.number.precision(.fractionLength(0...2)))
        let enteredSum = fragranceDrafts.reduce(0) { $0 + $1.amount }
        return FragranceTarget(
            text: "\(amountText) \(unit) (\(formatPercentage(fragranceTargetPercentage))%)",
            percentage: fragranceTargetPercentage,
            isOverTarget: target > 0 && enteredSum > target * 1.005
        )
    }

    /// Sum of the blend shares, non-nil only in `% of fragrances` mode. Drives
    /// the warning shown when the shares don't add up to 100%.
    var fragranceBlendTotal: Double? {
        guard fragranceUnit == .percentOfFragrances, !fragranceDrafts.isEmpty else { return nil }
        return fragranceDrafts.reduce(0) { $0 + $1.amount }
    }

    // MARK: - Mutation

    func addFragrance(_ ingredient: Ingredient) {
        guard !fragranceDrafts.contains(where: {
            $0.ingredient.persistentModelID == ingredient.persistentModelID
        }) else { return }
        fragranceDrafts.append(IngredientAmountDraft(ingredient: ingredient, unit: fragranceUnit.rawValue))
        redistributeFragrancePercentages()
    }

    func removeFragrance(at offsets: IndexSet) {
        fragranceDrafts.remove(atOffsets: offsets)
        redistributeFragrancePercentages()
    }

    func userEditedFragrance(id: UUID, amount: Double) {
        guard let idx = fragranceDrafts.firstIndex(where: { $0.id == id }) else { return }
        fragranceDrafts[idx].amount = amount
        guard redistributionTotal != nil else { return }
        fragranceDrafts[idx].isLocked = true
        redistributeFragrancePercentages()
    }

    /// Switches the recipe-wide fragrance unit, stamping every draft and
    /// clearing the locks the old basis accumulated. Entering `% of fragrances`
    /// re-expresses the current amounts as shares of their own sum, preserving
    /// the blend the user already built; entering `% of oils` redistributes the
    /// target load evenly; the absolute units keep the entered numbers.
    func setFragranceUnit(_ unit: FragranceUnit) {
        guard unit != fragranceUnit else { return }
        fragranceUnit = unit
        for idx in fragranceDrafts.indices {
            fragranceDrafts[idx].unit = unit.rawValue
            fragranceDrafts[idx].isLocked = false
        }
        switch unit {
        case .percentOfFragrances:
            normalizeFragranceShares()
        case .percentOfOils:
            redistributeFragrancePercentages()
        case .grams, .ounces, .milliliters, .percentOfBatch, .percentOfLiquids:
            break
        }
    }

    /// Adopts the recipe's stored unit and locks the rows that came with it, so
    /// what the user saved survives the rest of the session.
    ///
    /// Locking is what separates editing from creating. A new recipe's rows are
    /// all unlocked, so each fragrance added splits the total afresh — three
    /// fragrances land on a third each. A saved recipe's rows are locked, so
    /// adding a fourth to a 60/40 blend leaves it at 60/40 and gives the new
    /// row what is left, which is nothing until the user rebalances. Rewriting
    /// the saved amounts would throw away the numbers they are editing against.
    ///
    /// Only the units that spread a budget across the rows need the lock; the
    /// absolute ones never redistribute, so their amounts stand on their own.
    func lockLoadedFragranceRows(with unit: FragranceUnit) {
        fragranceUnit = unit
        let redistributes = redistributionTotal != nil
        for idx in fragranceDrafts.indices {
            fragranceDrafts[idx].isLocked = redistributes
            fragranceDrafts[idx].unit = unit.rawValue
        }
    }

    // MARK: - Redistribution

    /// The total the fragrance rows should sum to in the units that spread a
    /// budget across the rows — the recipe's fragrance load for `% of oils`,
    /// 100 for shares of the blend — and `nil` for the units that don't.
    private var redistributionTotal: Double? {
        switch fragranceUnit {
        case .percentOfOils: fragranceTargetPercentage
        case .percentOfFragrances: 100
        case .grams, .ounces, .milliliters, .percentOfBatch, .percentOfLiquids: nil
        }
    }

    /// Re-expresses the current amounts as shares of their own sum totalling
    /// 100 (18 g / 12 g → 60 / 40), falling back to an even split when there is
    /// nothing to preserve.
    private func normalizeFragranceShares() {
        let sum = fragranceDrafts.reduce(0) { $0 + $1.amount }
        guard sum > 0 else {
            redistributeFragrancePercentages()
            return
        }
        for idx in fragranceDrafts.indices.dropLast() {
            fragranceDrafts[idx].amount = (fragranceDrafts[idx].amount / sum * 1000).rounded() / 10
        }
        if let last = fragranceDrafts.indices.last {
            let assigned = fragranceDrafts.dropLast().reduce(0) { $0 + $1.amount }
            fragranceDrafts[last].amount = max(0, 100 - assigned)
        }
    }

    private func redistributeFragrancePercentages() {
        guard let target = redistributionTotal else { return }
        let lockedSum = fragranceDrafts.filter(\.isLocked).reduce(0) { $0 + $1.amount }
        let remaining = max(0, target - lockedSum)
        let unlockedIndices = fragranceDrafts.indices.filter { !fragranceDrafts[$0].isLocked }
        guard !unlockedIndices.isEmpty else { return }
        let share = (remaining / Double(unlockedIndices.count) * 10).rounded() / 10
        for (enumIdx, idx) in unlockedIndices.enumerated() {
            if enumIdx == unlockedIndices.count - 1 {
                let assignedSum = unlockedIndices.dropLast().reduce(0.0) { $0 + fragranceDrafts[$1].amount }
                fragranceDrafts[idx].amount = max(0, remaining - assignedSum)
            } else {
                fragranceDrafts[idx].amount = share
            }
        }
    }
}
