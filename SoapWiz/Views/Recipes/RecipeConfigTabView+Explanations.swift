import Foundation

/// The info popovers' copy for the Config tab's soap method toggles.
extension RecipeConfigTabView {
    /// Explains what the toggle surfaces. The two fractions are the same constants
    /// `LyeCalculator` scales the amounts by, so the quoted percentages can't drift
    /// from the numbers shown in the tables.
    var creamSoapExplanation: String {
        let water = LyeCalculator.creamSoapWaterFraction
            .formatted(.percent.precision(.fractionLength(0...2)))
        let glycerine = LyeCalculator.creamSoapGlycerineFraction
            .formatted(.percent.precision(.fractionLength(0...2)))
        return "Cream soap is a soft, whippable soap. Turning this on adds the extra "
            + "water and glycerine it needs, scaled to the oil weight and whipped in after "
            + "the cook to dilute.\n\n"
            + "The additional water (\(water) of the oil weight) appears in the calculated "
            + "amounts — it's free, so it's never costed. Glycerine (\(glycerine)) drops into "
            + "your ingredients as a costed extra when you have it in stock; otherwise it's "
            + "suggested under Extra Ingredients."
    }

    /// Liquid-soap method described in Catherine Failor's *Making Natural Liquid
    /// Soaps*, as implemented in `LyeCalculator`. The dose is quoted in the
    /// recipe's own units: Failor's ¾ oz per lb when the recipe is measured in
    /// oz or lb, the metric equivalent otherwise.
    var cfmExplanation: String {
        "Takes the lye at 0% super fat plus a 10% excess so every oil saponifies, "
        + "then neutralises what's left over after the cook. Water is still sized "
        + "from the recipe's normal super-fat lye, so the excess doesn't dilute the batch.\n\n"
        + "The neutraliser is \(cfmDoseDescription) — boric acid at 20% solid "
        + "to 80% water, or borax at 33% to 67%. The dose is shown with the calculated "
        + "amounts and, once a neutraliser ingredient is chosen, costed and deducted "
        + "from inventory like the lye."
    }

    /// Failor's ¾ oz of solution per lb of soap, or the same fraction expressed
    /// as grams per kilogram for a metric recipe — derived from the calculator's
    /// constant rather than typed out, so the two can't drift apart.
    private var cfmDoseDescription: String {
        if model.usesImperialUnits {
            return "¾ oz of solution per lb of soap"
        }
        let gramsPerKilogram = (LyeCalculator.cfmNeutralizerSolutionFraction * 1000)
            .formatted(.number.precision(.fractionLength(0)))
        return "about \(gramsPerKilogram) g of solution per kg of soap"
    }
}
