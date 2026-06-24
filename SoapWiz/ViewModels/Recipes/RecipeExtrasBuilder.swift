import Foundation

/// Builds the suggested extra-ingredients table (sodium lactate, citric acid,
/// chelators, antioxidants…) shown beneath a recipe's ingredients, including the
/// acid-neutralisation lye sub-rows split by the recipe's lye ratio.
struct RecipeExtrasBuilder {
    let lye: LyeCalculator
    let fragranceTargetPercentage: Double
    let isCreamSoap: Bool

    /// Cream-soap recommended additions, scaled to total oil weight: extra water
    /// (0.792×) and glycerine (0.0625×). `nil` unless cream soap is on and the
    /// recipe has oils. Surfaced above the standard extras table.
    var creamSoapAdditions: [ExtraSectionBRow]? {
        guard isCreamSoap else { return nil }
        let oils = lye.totalOilBatchWeight
        guard oils > 0 else { return nil }
        return [
            ExtraSectionBRow(label: "Additional Water for Cream Soap", minValue: oils * 0.792),
            ExtraSectionBRow(label: "Glycerine for Cream Soap", minValue: oils * 0.0625)
        ]
    }

    var extraIngredientData: (sectionA: [ExtraSectionARow], sectionB: [ExtraSectionBRow])? {
        guard lye.oilAmountCalculations != nil,
              let totalLye = lye.calculatedLyeAmount,
              let totalWater = lye.calculatedWaterAmount else { return nil }

        let oils = lye.totalOilBatchWeight
        guard oils > 0 else { return nil }

        let batchTotal = oils + totalLye + totalWater
        let naohAcidMultiplier = lye.naohAcidMultiplier
        let kohAcidMultiplier = lye.kohAcidMultiplier

        // Extra lye to neutralise each acid, split by the recipe's lye ratio. A
        // side with no lye (nil multiplier) is omitted so the extras table drops
        // that subrow.
        func triple(_ val1: Double, _ val2: Double, _ val3: Double, factor: Double, multiplier: Double?) -> LyeTriple? {
            guard let multiplier else { return nil }
            let scale = factor * multiplier
            return LyeTriple(val1: val1 * scale, val2: val2 * scale, val3: val3 * scale)
        }
        func single(_ amount: Double, factor: Double, multiplier: Double?) -> Double? {
            guard let multiplier else { return nil }
            return amount * factor * multiplier
        }

        let citric1 = oils * 0.01
        let citric2 = oils * 0.02
        let citric3 = oils * 0.03
        let sectionA: [ExtraSectionARow] = [
            ExtraSectionARow(label: "Sodium Lactate (60%)", val1: oils * 0.01, val2: oils * 0.02, val3: oils * 0.03),
            ExtraSectionARow(
                label: "Citric Acid Powder",
                val1: citric1, val2: citric2, val3: citric3,
                naohLye: triple(citric1, citric2, citric3, factor: 0.625, multiplier: naohAcidMultiplier),
                kohLye: triple(citric1, citric2, citric3, factor: 0.625, multiplier: kohAcidMultiplier)
            )
        ]

        let ascorbic = oils * 0.01
        let lactic = oils * 0.0075
        let sectionB: [ExtraSectionBRow] = [
            ExtraSectionBRow(label: "EO / Fragrance Oil", minValue: oils * fragranceTargetPercentage / 100),
            ExtraSectionBRow(label: "Ascorbic Acid", minValue: ascorbic,
                naohLye: single(ascorbic, factor: 0.2020, multiplier: naohAcidMultiplier),
                kohLye: single(ascorbic, factor: 0.2020, multiplier: kohAcidMultiplier)),
            ExtraSectionBRow(label: "Lactic Acid", minValue: lactic,
                naohLye: single(lactic, factor: 0.5920, multiplier: naohAcidMultiplier),
                kohLye: single(lactic, factor: 0.5920, multiplier: kohAcidMultiplier)),
            ExtraSectionBRow(label: "Tetrasodium EDTA", minValue: batchTotal * 0.005),
            ExtraSectionBRow(label: "Sodium Citrate", minValue: oils * 0.013, maxValue: oils * 0.039),
            ExtraSectionBRow(label: "Potassium Citrate", minValue: oils * 0.016, maxValue: oils * 0.048),
            ExtraSectionBRow(label: "Rosemary Oleoresin (ROE)", minValue: oils * 0.0004, maxValue: oils * 0.0005)
        ]

        return (sectionA, sectionB)
    }
}
