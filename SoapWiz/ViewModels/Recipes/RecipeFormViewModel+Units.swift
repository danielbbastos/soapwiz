import Foundation

/// The recipe's percentage scale and the units its rows are measured in.
///
/// Split from the view model's live editing state because the two answer
/// different questions: what the user is holding versus how the amounts they
/// typed resolve. `percentageAdditiveTotal`, `redistributePercentages` and
/// `rebalanceForSharedPercentageScale` are internal rather than private only so
/// they can live here — nothing outside the view model calls them.
extension RecipeFormViewModel {
    /// What the Ingredients section's running total shows. On a non-soap recipe
    /// the base rows and the percentage additives share one 100% scale, so both
    /// count toward it; a soap recipe keeps additives on top of an oil total
    /// that is already 100%, which is the soap-making convention.
    var totalPercentage: Double {
        oilDrafts.reduce(0) { $0 + $1.amount } + (makesSoap ? 0 : percentageAdditiveTotal)
    }

    /// Sum of the additive rows entered as a share of the total. Only these
    /// participate in the 100% scale — a gram or a count doesn't.
    var percentageAdditiveTotal: Double {
        additiveDrafts
            .filter { $0.unit == RecipeUnitOptions.percentOfTotal }
            .reduce(0) { $0 + $1.amount }
    }

    /// Default unit for a mass row.
    ///
    /// On a soap recipe additives are conventionally entered as a weight, so
    /// they default to grams in percentage mode (rather than "% of oils") to
    /// avoid silently applying a percentage of the oils. A non-soap recipe in
    /// percentage mode defaults to the shared "% of total" scale instead, so a
    /// formula reads as one set of percentages rather than a mix of percentages
    /// and weights.
    var defaultAdditiveUnit: String {
        guard weightUnitIsPercentage else { return weightUnit }
        return makesSoap ? "g" : RecipeUnitOptions.percentOfTotal
    }

    /// The unit a row takes for this ingredient.
    ///
    /// On a non-soap recipe this is the whole story — units are derived, never
    /// chosen, so a formula reads in one unit throughout. An ingredient stocked
    /// by the piece is a component rather than part of the mixture and stays a
    /// count in either kind: no percentage of a wick means anything.
    func derivedUnit(for ingredient: Ingredient) -> String {
        ingredient.unit == RecipeUnitOptions.count ? RecipeUnitOptions.count : defaultAdditiveUnit
    }

    /// How a row's unit reads in the ingredients list. A non-soap recipe has one
    /// percentage scale, so "% of total" is shown as plain "%" — the same thing
    /// the base rows show, which is what makes the merged section read as one
    /// list. The stored value keeps its longer name, which is what distinguishes
    /// it from soap's "% of oils".
    func unitLabel(for unit: String) -> String {
        unit == RecipeUnitOptions.percentOfTotal ? "%" : unit
    }

    /// Rewrites the units the current kind can't express, leaving the rest alone.
    ///
    /// A non-soap recipe has exactly one mass unit — whatever the Config tab
    /// declared — so anything else becomes it. A soap recipe can't express
    /// "% of total", so only that is rewritten; its own "% of oils", grams and
    /// millilitres are deliberate choices and survive a round trip through the
    /// other kind. Counts are never touched.
    ///
    /// Called from the kind and measurement-unit setters, and once more at the
    /// end of `load` — the drafts are assigned after both of those, so the
    /// setters' own reconcile hasn't seen them.
    func reconcileAdditiveUnits() {
        for index in additiveDrafts.indices {
            let unit = additiveDrafts[index].unit
            guard !RecipeUnitOptions.isCount(unit) else { continue }
            let cannotExpress = makesSoap
                ? unit == RecipeUnitOptions.percentOfTotal
                : unit != defaultAdditiveUnit
            if cannotExpress { additiveDrafts[index].unit = defaultAdditiveUnit }
        }
    }

    /// Rescales the base rows after an additive changed, so they and the
    /// percentage additives still total 100%. A soap recipe's additives sit
    /// outside the oil total, so nothing needs rebalancing there.
    ///
    /// Proportional, rather than the equal-share redistribution `addOil` uses:
    /// the base rows are a formula whose ratios the maker chose, and making room
    /// for 5% of an additive shouldn't flatten a 60/40 blend into 47.5/47.5.
    /// Scaling also works when every base row is locked, which is how they all
    /// come back from `load` — the equal-share path bails out there, which left
    /// a reopened recipe totalling more than 100.
    func rebalanceForSharedPercentageScale() {
        guard !makesSoap, weightUnitIsPercentage, !oilDrafts.isEmpty else { return }
        let target = max(0, 100 - percentageAdditiveTotal)
        let baseTotal = oilDrafts.reduce(0) { $0 + $1.amount }
        guard baseTotal > 0, abs(baseTotal - target) > 0.0001 else { return }

        // The last row takes the remainder rather than its own scaled value, so
        // rounding each row to a tenth can't leave the formula off 100.
        let factor = target / baseTotal
        var assigned = 0.0
        for index in oilDrafts.indices.dropLast() {
            let scaled = (oilDrafts[index].amount * factor * 10).rounded() / 10
            oilDrafts[index].amount = scaled
            assigned += scaled
        }
        if let last = oilDrafts.indices.last {
            oilDrafts[last].amount = max(0, target - assigned)
        }
    }

    /// Shares the remainder of the 100% scale across the unlocked base rows.
    ///
    /// On a non-soap recipe the percentage additives are claimants on the same
    /// 100 as the base rows, so they count against the remainder exactly like a
    /// locked base row: setting an additive to 1% pulls the base rows down to
    /// 99% between them rather than pushing the formula to 101%.
    func redistributePercentages() {
        let lockedOils = oilDrafts.filter(\.isLocked).reduce(0) { $0 + $1.amount }
        let lockedSum = lockedOils + (makesSoap ? 0 : percentageAdditiveTotal)
        let remaining = max(0, 100 - lockedSum)
        let unlockedIndices = oilDrafts.indices.filter { !oilDrafts[$0].isLocked }
        guard !unlockedIndices.isEmpty else { return }
        let share = (remaining / Double(unlockedIndices.count) * 10).rounded() / 10
        for (enumIdx, idx) in unlockedIndices.enumerated() {
            if enumIdx == unlockedIndices.count - 1 {
                let assignedSum = unlockedIndices.dropLast().reduce(0.0) { $0 + oilDrafts[$1].amount }
                oilDrafts[idx].amount = max(0, remaining - assignedSum)
            } else {
                oilDrafts[idx].amount = share
            }
        }
    }
}
