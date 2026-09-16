import Testing
import Foundation
@testable import SoapWiz

@Suite("Ingredient library data")
@MainActor
struct IngredientLibraryDataTests {

    private let entries = IngredientLibrary.bundled.entries

    private static let lipidCategories: Set<String> = [
        IngredientCategory.Name.oils,
        IngredientCategory.Name.fats,
        IngredientCategory.Name.waxes
    ]

    private static let freeFattyAcidSlugs: Set<String> = [
        "lauric-acid", "myristic-acid", "palmitic-acid", "stearic-acid", "oleic-acid", "commercial-stearic-acid"
    ]

    /// Lipids whose published SAP doesn't follow from their tracked acids, with the reason.
    private static let estimateExemptSlugs: [String: String] = [
        "shea-butter": "5–10% unsaponifiable matter",
        "nutmeg-butter": "about 10% unsaponifiable matter",
        "carrot-seed-oil": "sold as a macerate, so much of its weight doesn't saponify",
        "chinese-vegetable-tallow": "measured SV 185–195 is below what its palmitic-heavy profile implies"
    ]

    private static let molecularWeights: [(acid: KeyPath<FattyAcidProfile, Double>, weight: Double)] = [
        (\.lauric, 200.32),
        (\.myristic, 228.37),
        (\.palmitic, 256.42),
        (\.stearic, 284.48),
        (\.oleic, 282.46),
        (\.linoleic, 280.45),
        (\.linolenic, 278.43),
        (\.ricinoleic, 298.46)
    ]

    private var lipids: [IngredientLibraryEntry] {
        entries.filter { Self.lipidCategories.contains($0.category) }
    }

    // MARK: - Identity

    @Test func bundled_Decodes_WithEntries() {
        #expect(!entries.isEmpty)
    }

    @Test func slugs_AreUniqueKebabCase() {
        let slugs = entries.map(\.slug)
        let malformed = slugs.filter { !isKebabCase($0) }
        #expect(malformed.isEmpty, "Malformed slugs: \(malformed)")
        #expect(slugs.count == Set(slugs).count)
    }

    @Test func namesAndAliases_AreUniqueByLookupKey() {
        let keys = entries.flatMap { [$0.name] + $0.aliases }.map(\.lookupKey)
        let duplicates = Dictionary(grouping: keys, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        #expect(duplicates.isEmpty, "Names or aliases shared by more than one entry: \(duplicates)")
    }

    @Test func categories_AreKnownCategoryNames() {
        let unknown = entries.filter { !IngredientCategory.Name.all.contains($0.category) }
        #expect(unknown.isEmpty, "Unknown categories: \(unknown.map(\.slug))")
    }

    @Test func units_AreIngredientUnits() {
        let unknown = entries.filter { IngredientUnit(rawValue: $0.unit) == nil }
        #expect(unknown.isEmpty, "Unknown units: \(unknown.map(\.slug))")
    }

    // MARK: - Chemistry presence

    @Test func lipids_HaveSapValuesAndProfile() {
        let incomplete = lipids.filter { $0.sapValue == nil || $0.kohSapValue == nil || $0.fattyAcidProfile == nil }
        #expect(incomplete.isEmpty, "Lipids missing chemistry: \(incomplete.map(\.slug))")
    }

    @Test func nonLipids_HaveNoSapValuesOrProfile() {
        let nonLipids = entries.filter { !Self.lipidCategories.contains($0.category) }
        let withChemistry = nonLipids.filter { $0.sapValue != nil || $0.kohSapValue != nil || $0.fattyAcidProfile != nil }
        #expect(withChemistry.isEmpty, "Non-lipids with chemistry: \(withChemistry.map(\.slug))")
    }

    // MARK: - Plausibility

    @Test func fattyAcidProfiles_SumToAtMost101() {
        let overfull = lipids.filter { total(of: $0.fattyAcidProfile) > 101 }
        #expect(overfull.isEmpty, "Profiles over 100%: \(overfull.map(\.slug))")
    }

    @Test func fattyAcidProfiles_AcidsWithinZeroToHundred() {
        let invalid = lipids.filter { entry in
            guard let profile = entry.fattyAcidProfile else { return false }
            return Self.molecularWeights.contains { !(0...100).contains(profile[keyPath: $0.acid]) }
        }
        #expect(invalid.isEmpty, "Acids outside 0–100: \(invalid.map(\.slug))")
    }

    @Test func kohSapValue_IsSapValueTimesMolarMassRatio() {
        let mismatched = lipids.filter { entry in
            guard let sap = entry.sapValue, let koh = entry.kohSapValue else { return false }
            return abs(koh - sap * 1.4025) > 0.0015
        }
        #expect(mismatched.isEmpty, "KOH SAP not NaOH SAP × 1.4025: \(mismatched.map(\.slug))")
    }

    @Test func kohSapValues_WithinPlausibleRange() {
        let implausible = lipids.filter { entry in
            guard let koh = entry.kohSapValue else { return false }
            return !(0.040...0.350).contains(koh)
        }
        #expect(implausible.isEmpty, "KOH SAP outside 0.040–0.350: \(implausible.map(\.slug))")
    }

    @Test func densities_WithinPlausibleRange() {
        let implausible = entries.filter { entry in
            guard let density = entry.density else { return false }
            return !(0.80...1.40).contains(density)
        }
        #expect(implausible.isEmpty, "Density outside 0.80–1.40: \(implausible.map(\.slug))")
    }

    @Test func kohSapValue_NearCompleteProfile_MatchesProfileEstimate() {
        let mismatched = lipids.compactMap { entry -> String? in
            guard Self.estimateExemptSlugs[entry.slug] == nil,
                  let koh = entry.kohSapValue,
                  let profile = entry.fattyAcidProfile,
                  total(of: profile) >= 95 else { return nil }
            let estimate = estimatedKohSapValue(for: profile, asFreeAcids: Self.freeFattyAcidSlugs.contains(entry.slug))
            let deviation = abs(koh - estimate) / estimate
            return deviation > 0.07 ? "\(entry.slug) \(koh) vs \(estimate)" : nil
        }
        #expect(mismatched.isEmpty, "KOH SAP more than 7% from the profile estimate: \(mismatched)")
    }

    // MARK: - Helpers

    private func isKebabCase(_ slug: String) -> Bool {
        slug.split(separator: "-", omittingEmptySubsequences: false).allSatisfy { part in
            !part.isEmpty && part.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
        }
    }

    private func total(of profile: FattyAcidProfile?) -> Double {
        guard let profile else { return 0 }
        return Self.molecularWeights.reduce(0) { $0 + profile[keyPath: $1.acid] }
    }

    /// Grams of KOH per gram of fat, assuming the tracked acids are the whole fat:
    /// a triglyceride carries three acids on one glycerol backbone, a free acid none.
    private func estimatedKohSapValue(for profile: FattyAcidProfile, asFreeAcids: Bool) -> Double {
        let potassiumHydroxide = 56.106
        let tracked = total(of: profile)
        return Self.molecularWeights.reduce(0) { sum, pair in
            let share = profile[keyPath: pair.acid] / tracked
            let perAcid = asFreeAcids
                ? potassiumHydroxide / pair.weight
                : 3 * potassiumHydroxide / (3 * pair.weight + 38.05)
            return sum + share * perAcid
        }
    }
}
