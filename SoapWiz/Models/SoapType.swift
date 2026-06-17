import Foundation

/// The kind of soap a recipe's lye configuration produces. Drives a descriptive
/// label in the recipe form and stats — the classification mirrors LyeCalc.
enum SoapType: String {
    case solid
    case cream
    case liquid

    var label: String {
        switch self {
        case .solid: "Solid bar soap"
        case .cream: "Cream soap"
        case .liquid: "Liquid soap"
        }
    }

    /// Classifies the soap from the lye configuration.
    ///
    /// - Hybrid: a meaningful NaOH share (> 10%) yields a soft **cream**;
    ///   otherwise (KOH-dominant) it's **liquid**.
    /// - Single lye: KOH makes **liquid** soap, NaOH makes a **solid** bar.
    static func classify(
        useHybrid: Bool,
        naohPercentage: Double,
        lyeType: String
    ) -> SoapType {
        if useHybrid {
            return naohPercentage > 10 ? .cream : .liquid
        }
        return lyeType == "KOH" ? .liquid : .solid
    }
}
