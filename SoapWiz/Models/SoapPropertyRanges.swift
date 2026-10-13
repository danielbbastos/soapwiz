import Foundation
import SwiftUI

enum SoapQuality: String, CaseIterable, Identifiable {
    case hardness, cleansing, conditioning, bubbly, creamy, longevity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hardness: "Hardness"
        case .cleansing: "Cleansing"
        case .conditioning: "Conditioning"
        case .bubbly: "Bubbly"
        case .creamy: "Creamy"
        case .longevity: "Longevity"
        }
    }

    var shortName: String {
        switch self {
        case .hardness: "Hard"
        case .cleansing: "Clean"
        case .conditioning: "Cond"
        case .bubbly: "Bub"
        case .creamy: "Cream"
        case .longevity: "Life"
        }
    }

    var recommendedRange: ClosedRange<Double> {
        switch self {
        case .hardness: 29...54
        case .cleansing: 12...22
        case .conditioning: 44...69
        case .bubbly: 14...46
        case .creamy: 16...48
        case .longevity: 16...48
        }
    }

    /// What the quality means for the bar and where it comes from, shown beside
    /// the quality's bar on a single oil. The ranges repeat `recommendedRange`.
    var explanation: String {
        switch self {
        case .hardness:
            "How firm the bar will be and how easily it comes out of the mold. "
            + "It comes from the saturated fatty acids: lauric, myristic, palmitic and stearic. "
            + "29 to 54 is the usual target. Lower blends make soft bars that dent easily."
        case .cleansing:
            "How strongly the soap strips oil from the skin. "
            + "It comes from lauric and myristic acids, found mostly in coconut and palm kernel oils. "
            + "12 to 22 is the usual target. Higher blends can leave skin feeling dry, "
            + "which a higher superfat helps soften."
        case .conditioning:
            "How mild the bar feels on the skin. "
            + "It comes from the unsaturated fatty acids: oleic, linoleic, linolenic and ricinoleic. "
            + "44 to 69 is the usual target, but soaps rich in olive oil score well above it "
            + "and are still excellent."
        case .bubbly:
            "How much big, fluffy lather the bar makes. "
            + "It comes from lauric, myristic and ricinoleic acids, found mostly in coconut and castor oils. "
            + "14 to 46 is the usual target. These bubbles build quickly but fade fast."
        case .creamy:
            "How dense and stable the lather is: the fine, lotion-like foam that stays on the skin. "
            + "It comes from palmitic, stearic and ricinoleic acids, found in butters, tallow and castor oil. "
            + "16 to 48 is the usual target. Raising bubbly lather tends to lower creamy lather, "
            + "and the other way round."
        case .longevity:
            "How long the bar lasts in use. "
            + "It comes from palmitic and stearic acids, whose soaps dissolve slowly in water. "
            + "16 to 48 is the usual target. A hard bar isn't always a long-lasting one: "
            + "coconut oil makes a hard bar that still wears away quickly."
        }
    }

    var color: Color {
        switch self {
        case .hardness: .chartHardness
        case .cleansing: .chartCleansing
        case .conditioning: .chartConditioning
        case .bubbly: .chartBubbly
        case .creamy: .chartCreamy
        case .longevity: .chartLongevity
        }
    }

    func value(from profile: FattyAcidProfile) -> Double {
        switch self {
        case .hardness: profile.hardness
        case .cleansing: profile.cleansing
        case .conditioning: profile.conditioning
        case .bubbly: profile.bubbly
        case .creamy: profile.creamy
        case .longevity: profile.longevity
        }
    }
}

enum SoapMetric {
    static let insRange: ClosedRange<Double> = 136...170
    static let insScale: ClosedRange<Double> = 0...320
    static let iodineRange: ClosedRange<Double> = 41...70
    static let iodineScale: ClosedRange<Double> = 0...200
}
