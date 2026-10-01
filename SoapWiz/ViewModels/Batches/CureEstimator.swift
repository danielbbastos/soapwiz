import Foundation

/// Which rule of thumb a solid bar's cure falls under. Each range is one that
/// soap makers publish for that kind of bar, not a figure of SoapWiz's own:
///
/// - Typical cold process, 4–6 weeks: Soap Queen (Bramble Berry), Lovely Greens.
/// - Typical hot process, 2–4 weeks: Modern Soapmaking cures hers two weeks;
///   Soap Queen and the Ultimate Guide to Soap give up to four for a harder bar.
/// - High olive, 6–8 weeks: a bastile of 80% olive and 20% coconut.
/// - Castile, 6 weeks to 6 months: Lovely Greens and Soap Queen give six weeks
///   at the least, and six months to a year for the best bar.
///
/// A soft blend keeps its band when hot processed. Cooking drives water off,
/// but the slow change in an olive soap's crystal structure goes on for months
/// however the bar was made.
///
/// Stored on the batch by raw value, so its recommended range outlives the
/// recipe; the raw values must never change.
enum CureBand: String, Equatable {
    case typicalCold
    case typicalHot
    case highOlive
    case castile

    var weeks: ClosedRange<Int> {
        switch self {
        case .typicalCold: 4...6
        case .typicalHot: 2...4
        case .highOlive: 6...8
        case .castile: 6...26
        }
    }

    /// The recommended range as soap makers say it.
    var rangeText: String {
        switch self {
        case .typicalCold: "4–6 weeks"
        case .typicalHot: "2–4 weeks"
        case .highOlive: "6–8 weeks"
        case .castile: "6 weeks to 6 months"
        }
    }

    /// The shortest recommended cure: from here the bars can be used, though
    /// they keep improving until the cure the batch was given.
    var usableDays: Int { weeks.lowerBound * 7 }

    /// The band a batch stored, or `nil` for one that doesn't cure or was
    /// made before bands were recorded.
    static func resolve(_ raw: String) -> CureBand? {
        CureBand(rawValue: raw)
    }

    /// The range and why, as the Create Batch footer shows it.
    var summary: String { "\(rangeText): \(reason)" }

    private var reason: String {
        switch self {
        case .typicalCold: "typical for a cold-process bar."
        case .typicalHot: "a hot-process bar has less water left to lose."
        case .highOlive: "soft, high-olive blends take longer to harden."
        case .castile: "castile-style bars keep improving for up to a year."
        }
    }
}

/// A suggested cure, shown as a range with the longer end as the default.
struct CureEstimate: Equatable {
    let band: CureBand

    var weeks: ClosedRange<Int> { band.weeks }
    var defaultDays: Int { weeks.upperBound * 7 }
}

/// Suggests how long a batch should cure, from what its recipe makes and how
/// soft its oils are.
///
/// Softness is read off the blend's hardness (lauric + myristic + palmitic +
/// stearic), the figure the recipe stats already show. Below the bottom of the
/// recommended hardness range (29) the bar counts as high olive: an 80/20
/// olive and coconut bastile sits near 27. Below 20 it counts as castile: pure
/// olive oil sits near 14, and 20 is roughly 90% olive. These two cut-offs are
/// SoapWiz's own, set between those anchor recipes; the published ranges are
/// in `CureBand`.
///
/// Water isn't weighed in. Soap Queen holds that a water discount shortens the
/// cure; experienced makers on the Soap Making Forum find it only firms the
/// bar sooner and still give it four weeks. With the sources split, the
/// estimate doesn't move either way.
enum CureEstimator {
    static let highOliveHardness = SoapQuality.hardness.recommendedRange.lowerBound
    static let castileHardness = 20.0

    /// `nil` for anything but a solid bar. Liquid and cream soap and non-soap
    /// recipes don't cure, and a batch of one never mentions it.
    static func estimate(
        makesSoap: Bool,
        soapType: SoapType,
        fattyAcidProfile: FattyAcidProfile,
        process: SoapProcess
    ) -> CureEstimate? {
        guard makesSoap, soapType == .solid else { return nil }
        // Without any fatty acid data there's no softness to read, and an
        // all-zero hardness would otherwise pass for pure castile.
        guard !fattyAcidProfile.isEmpty else { return CureEstimate(band: typicalBand(for: process)) }

        let hardness = fattyAcidProfile.hardness
        if hardness < castileHardness { return CureEstimate(band: .castile) }
        if hardness < highOliveHardness { return CureEstimate(band: .highOlive) }
        return CureEstimate(band: typicalBand(for: process))
    }

    private static func typicalBand(for process: SoapProcess) -> CureBand {
        switch process {
        case .cold: .typicalCold
        case .hot: .typicalHot
        }
    }
}
