import Foundation

struct OilQualityContribution: Identifiable {
    let id: Int
    let oilName: String
    let value: Double
}

/// The blend's derived figures.
///
/// The fatty acid profile and the iodine value are compositional — they are the
/// weighted average of what each ingredient already is, and saponification
/// neither produces nor changes them. They hold for a balm or a candle exactly
/// as they do for soap. Everything else here is read off the SAP value, which is
/// by definition how much lye the fat consumes, so it is soap-only and `nil`
/// otherwise.
struct RecipeStats {
    let fattyAcidProfile: FattyAcidProfile
    let iodineValue: Double

    /// `nil` for a non-soap recipe: INS is `SAP × 1402.5 − iodine`, a bar-hardness
    /// heuristic with nothing to say about a candle.
    let ins: Double?

    /// Weighted lye-consumption factors. `nil` for a non-soap recipe.
    let totalNaOHSap: Double?
    let totalKOHSap: Double?
    let hasOils: Bool

    /// Whether any ingredient in the blend actually carries a fatty acid
    /// profile. Waxes are the common case that don't: beeswax and candelilla are
    /// wax esters rather than triglycerides, so a pure beeswax candle has oils
    /// but no composition to report — and a table of twelve `0.00 %` rows reads
    /// as a bug rather than as an absence.
    var hasFattyAcidData: Bool { fattyAcidProfile != .zero }

    /// Whether the soap qualities (hardness, cleansing, bubbly…) mean anything
    /// here. They map fatty acids onto how the *soap* behaves, so the numbers
    /// are computable for any blend but only interpretable for soap.
    let makesSoap: Bool
    private let oilSharedProfiles: [(name: String, profile: FattyAcidProfile)]

    init(oilDrafts: [OilIngredientDraft], makesSoap: Bool = true) {
        self.makesSoap = makesSoap
        let contributions: [(amount: Double, ingredient: Ingredient)] = oilDrafts.compactMap { draft in
            guard draft.amount > 0 else { return nil }
            return (draft.amount, draft.ingredient)
        }

        self.hasOils = !contributions.isEmpty

        let profileContribs = contributions.map { contrib in
            (profile: contrib.ingredient.fattyAcidProfile ?? .zero, weight: contrib.amount)
        }
        let profile = FattyAcidProfile.weightedSum(profileContribs)
        self.fattyAcidProfile = profile
        self.iodineValue = profile.iodineValue

        let totalWeight = contributions.reduce(0.0) { $0 + $1.amount }
        if totalWeight > 0 {
            self.oilSharedProfiles = contributions.map { contrib in
                let share = contrib.amount / totalWeight
                let profile = contrib.ingredient.fattyAcidProfile ?? .zero
                return (contrib.ingredient.name, profile.scaled(by: share))
            }
            let weightedNaOH = contributions.reduce(0.0) { acc, contrib in
                acc + (contrib.ingredient.sapValue ?? 0) * (contrib.amount / totalWeight)
            }
            let weightedKOH = contributions.reduce(0.0) { acc, contrib in
                acc + (contrib.ingredient.kohSapValue ?? 0) * (contrib.amount / totalWeight)
            }
            self.totalNaOHSap = makesSoap ? weightedNaOH : nil
            self.totalKOHSap = makesSoap ? weightedKOH : nil
            self.ins = makesSoap
                ? FattyAcidProfile.ins(naOHSapFactor: weightedNaOH, iodineValue: profile.iodineValue)
                : nil
        } else {
            self.oilSharedProfiles = []
            self.totalNaOHSap = makesSoap ? 0 : nil
            self.totalKOHSap = makesSoap ? 0 : nil
            self.ins = makesSoap ? 0 : nil
        }
    }

    func contributions(for quality: SoapQuality) -> [OilQualityContribution] {
        oilSharedProfiles.enumerated()
            .map { OilQualityContribution(id: $0.offset, oilName: $0.element.name, value: quality.value(from: $0.element.profile)) }
            .filter { $0.value > 0.01 }
            .sorted { $0.value > $1.value }
    }
}
