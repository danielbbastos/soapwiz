import Foundation

struct RecipeStats {
    let fattyAcidProfile: FattyAcidProfile
    let iodineValue: Double
    let ins: Double
    let totalNaOHSap: Double
    let totalKOHSap: Double
    let hasOils: Bool

    init(oilDrafts: [OilIngredientDraft]) {
        let contributions: [(amount: Double, ingredient: Ingredient)] = oilDrafts.compactMap { draft in
            let raw = draft.amount.replacingOccurrences(of: ",", with: ".")
            guard let amount = Double(raw), amount > 0 else { return nil }
            return (amount, draft.ingredient)
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
            let weightedNaOH = contributions.reduce(0.0) { acc, contrib in
                acc + (contrib.ingredient.sapValue ?? 0) * (contrib.amount / totalWeight)
            }
            let weightedKOH = contributions.reduce(0.0) { acc, contrib in
                acc + (contrib.ingredient.koHSapValue ?? 0) * (contrib.amount / totalWeight)
            }
            self.totalNaOHSap = weightedNaOH
            self.totalKOHSap = weightedKOH
            self.ins = FattyAcidProfile.ins(naOHSapFactor: weightedNaOH, iodineValue: profile.iodineValue)
        } else {
            self.totalNaOHSap = 0
            self.totalKOHSap = 0
            self.ins = 0
        }
    }
}
