import Foundation

struct FattyAcidProfile: Codable, Equatable {
    var lauric: Double = 0
    var myristic: Double = 0
    var palmitic: Double = 0
    var stearic: Double = 0
    var oleic: Double = 0
    var linoleic: Double = 0
    var linolenic: Double = 0
    var ricinoleic: Double = 0

    var saturated: Double { lauric + myristic + palmitic + stearic }
    var monoUnsaturated: Double { oleic }
    var polyUnsaturated: Double { linoleic + linolenic }

    var hardness: Double { lauric + myristic + palmitic + stearic }
    var cleansing: Double { lauric + myristic }
    var conditioning: Double { oleic + linoleic + linolenic + ricinoleic }
    var bubbly: Double { lauric + myristic + ricinoleic }
    var creamy: Double { palmitic + stearic + ricinoleic }
    var longevity: Double { palmitic + stearic }

    var iodineValue: Double {
        (oleic * 90 + linoleic * 181 + linolenic * 273 + ricinoleic * 86) / 100
    }

    static let zero = FattyAcidProfile()

    static func weightedSum(_ contributions: [(profile: FattyAcidProfile, weight: Double)]) -> FattyAcidProfile {
        let totalWeight = contributions.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return .zero }
        var result = FattyAcidProfile()
        for (profile, weight) in contributions {
            let share = weight / totalWeight
            result.lauric += profile.lauric * share
            result.myristic += profile.myristic * share
            result.palmitic += profile.palmitic * share
            result.stearic += profile.stearic * share
            result.oleic += profile.oleic * share
            result.linoleic += profile.linoleic * share
            result.linolenic += profile.linolenic * share
            result.ricinoleic += profile.ricinoleic * share
        }
        return result
    }

    static func ins(naOHSapFactor: Double, iodineValue: Double) -> Double {
        let sapKOH = naOHSapFactor * 1402.5
        return sapKOH - iodineValue
    }
}
