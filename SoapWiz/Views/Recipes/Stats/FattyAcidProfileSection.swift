import SwiftUI

/// The per-acid breakdown of the blend. Emits rows rather than a `Section` so
/// each call site keeps its own header and row background, matching
/// `SoapPropertiesSection`.
///
/// Shown for every recipe kind: the profile is the weighted composition of the
/// fats going in, which saponification does not change. Only the *reading* of it
/// is soap-specific, and that lives in `SoapPropertiesSection`.
struct FattyAcidBreakdownRows: View {
    let stats: RecipeStats

    var body: some View {
        FattyAcidRow("Lauric", stats.fattyAcidProfile.lauric)
        FattyAcidRow("Myristic", stats.fattyAcidProfile.myristic)
        FattyAcidRow("Palmitic", stats.fattyAcidProfile.palmitic)
        FattyAcidRow("Stearic", stats.fattyAcidProfile.stearic)
        FattyAcidRow("Oleic", stats.fattyAcidProfile.oleic)
        FattyAcidRow("Linoleic", stats.fattyAcidProfile.linoleic)
        FattyAcidRow("Linolenic", stats.fattyAcidProfile.linolenic)
        FattyAcidRow("Ricinoleic", stats.fattyAcidProfile.ricinoleic)
    }
}

/// The saturation totals, and the iodine value derived from them.
///
/// A section of its own rather than a `Divider` inside the breakdown: a bare
/// divider laid out as a list row draws as a stray vertical rule in an empty
/// row, and the grouped-list idiom for separating one group from the next is a
/// second section.
struct FattyAcidTotalsRows: View {
    let stats: RecipeStats

    /// Whether to append the iodine indicator. The soap layout already shows it
    /// alongside INS under Soap properties, so it would otherwise appear twice.
    var showsIodine: Bool = false

    var body: some View {
        FattyAcidRow("Saturated", stats.fattyAcidProfile.saturated)
        FattyAcidRow("Mono-unsaturated", stats.fattyAcidProfile.monoUnsaturated)
        FattyAcidRow("Poly-unsaturated", stats.fattyAcidProfile.polyUnsaturated)

        if showsIodine {
            SoapPropertyIndicatorView(
                title: "Iodine",
                value: stats.iodineValue,
                recommended: SoapMetric.iodineRange,
                scale: SoapMetric.iodineScale,
                infoTitle: "Iodine value",
                infoText: Self.iodineExplanation
            )
        }
    }

    /// Worded for a blend rather than a bar: the value measures unsaturation of
    /// the fats themselves, which is what drives rancidity whatever is made
    /// from them.
    private static let iodineExplanation =
        "The iodine value measures how unsaturated the oils are. Higher values mean a softer, "
        + "oilier blend that is more prone to going rancid (DOS); lower values keep longer and "
        + "set firmer. 41 to 70 is the usual target for a blend of soft and hard fats."
}

struct FattyAcidRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let label: String
    let value: Double

    init(_ label: String, _ value: Double) {
        self.label = label
        self.value = value
    }

    /// Whether the figure shows as 0.0 at the one decimal the row displays, so
    /// an acid that is absent reads as quiet rather than as a measured value.
    static func isEffectivelyZero(_ value: Double) -> Bool {
        abs(value) < 0.05
    }

    private var isZero: Bool { Self.isEffectivelyZero(value) }

    var body: some View {
        // One column at the accessibility sizes: beside the percentage, the
        // acid's name would be squeezed until it broke mid-word.
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                name
                percentage
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            HStack {
                name
                Spacer()
                percentage
            }
        }
    }

    private var name: some View {
        Text(label)
            .foregroundStyle(isZero ? Color.inkFaint : Color.ink)
    }

    private var percentage: some View {
        HStack(spacing: 8) {
            Text(value, format: .number.precision(.fractionLength(1)))
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(isZero ? Color.inkFaint : Color.inkSoft)
            Text("%")
                .foregroundStyle(isZero ? Color.inkFaint : Color.inkSoft)
        }
    }
}

/// Copy shared by the Stats tab and the recipe detail screen, so the two can't
/// drift apart.
enum RecipeStatsCopy {
    /// Header for the saturation totals that follow the per-acid breakdown.
    static let totalsHeader = "Totals"

    /// Shown when nothing in the blend carries a profile. Names waxes because
    /// they are the usual reason: a candle is often entirely wax esters, which
    /// have no triglyceride composition to break down.
    static let noFattyAcidData =
        "None of these ingredients has a fatty acid profile recorded. "
        + "Waxes usually don't, since they aren't triglycerides. Add an oil, fat or butter "
        + "to see the blend's composition."

    /// Shown on a single ingredient's own detail page when it has no profile yet.
    /// Singular and edit-oriented, where `noFattyAcidData` is worded for a blend.
    static let ingredientNoFattyAcidData =
        "No fatty acid profile recorded for this ingredient. Edit it to add one and "
        + "see the full composition and soap qualities."

    /// Warns that the soap-property breakdown under-reports because the named
    /// oils have no fatty acid data and so contribute nothing to it.
    static func incompleteSoapProperties(names: [String]) -> String {
        let list = names.formatted(.list(type: .and))
        let verb = names.count == 1 ? "has" : "have"
        return "Soap properties may be incomplete. \(list) \(verb) no fatty-acid data, "
            + "so this breakdown may be inaccurate."
    }
}
