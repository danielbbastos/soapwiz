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

    /// Why the range is what it is.
    var reason: String {
        switch self {
        case .typicalCold: "Typical for a cold-process bar."
        case .typicalHot: "A hot-process bar has less water left to lose."
        case .highOlive: "Soft, high-olive blends take longer to harden."
        case .castile: "Castile-style bars keep improving for up to a year."
        }
    }

    /// The soft-oil bands, which cooking doesn't shorten.
    var isSoft: Bool {
        switch self {
        case .highOlive, .castile: true
        case .typicalCold, .typicalHot: false
        }
    }
}

/// A suggested cure, shown as a range with the longer end as the default.
struct CureEstimate: Equatable {
    let band: CureBand
    let process: SoapProcess

    var weeks: ClosedRange<Int> { band.weeks }
    var defaultDays: Int { weeks.upperBound * 7 }

    /// The reason under the range, as the Create Batch footer shows it. A soft
    /// blend made hot says outright that cooking didn't shorten it, since the
    /// range is otherwise the same as cold.
    var explanation: String {
        guard process == .hot, band.isSoft else { return band.reason }
        return "\(band.reason) Hot process doesn't shorten this: soft-oil soaps keep hardening long after the cook."
    }
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
        return CureEstimate(band: band(for: fattyAcidProfile, process: process), process: process)
    }

    private static func band(for profile: FattyAcidProfile, process: SoapProcess) -> CureBand {
        // Without any fatty acid data there's no softness to read, and an
        // all-zero hardness would otherwise pass for pure castile.
        guard !profile.isEmpty else { return typicalBand(for: process) }

        let hardness = profile.hardness
        if hardness < castileHardness { return .castile }
        if hardness < highOliveHardness { return .highOlive }
        return typicalBand(for: process)
    }

    private static func typicalBand(for process: SoapProcess) -> CureBand {
        switch process {
        case .cold: .typicalCold
        case .hot: .typicalHot
        }
    }
}
