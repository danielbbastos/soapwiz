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
        FattyAcidRow("Saturated", stats.fattyAcidProfile.saturated, emphasis: true)
        FattyAcidRow("Mono-unsaturated", stats.fattyAcidProfile.monoUnsaturated, emphasis: true)
        FattyAcidRow("Poly-unsaturated", stats.fattyAcidProfile.polyUnsaturated, emphasis: true)

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
        + "set firmer. 41–70 is the usual target for a blend of soft and hard fats."
}

/// The fatty acid sections of the recipe form's Stats tab. The recipe detail
/// lays the same rows out in its own ledger sheets (`RecipeDetailStatsSections`).
/// Emits `Section`s, so it must sit directly inside a `List` or `Form`.
///
/// Shown for both kinds. A non-soap recipe carries the iodine value here,
/// since it has no Soap properties section to host it.
///
/// When the explanation stands in for the profile is decided by
/// `RecipeStats.showsMissingFattyAcidExplanation`.
struct FattyAcidProfileSections: View {
    let stats: RecipeStats

    @ViewBuilder
    var body: some View {
        if stats.hasFattyAcidData {
            Section("Fatty acid profile") {
                FattyAcidBreakdownRows(stats: stats)
            }
            Section(RecipeStatsCopy.totalsHeader) {
                FattyAcidTotalsRows(stats: stats, showsIodine: !stats.makesSoap)
            }
        } else if stats.showsMissingFattyAcidExplanation {
            Section("Fatty acid profile") {
                Text(RecipeStatsCopy.noFattyAcidData)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FattyAcidRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let label: String
    let value: Double
    var emphasis: Bool = false

    init(_ label: String, _ value: Double, emphasis: Bool = false) {
        self.label = label
        self.value = value
        self.emphasis = emphasis
    }

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
            .fontWeight(emphasis ? .semibold : .regular)
            .foregroundStyle(Color.ink)
    }

    private var percentage: some View {
        HStack(spacing: 8) {
            Text(value, format: .number.precision(.fractionLength(2)))
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(emphasis ? Color.ink : Color.inkSoft)
            Text("%")
                .foregroundStyle(Color.inkSoft)
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
        + "Waxes usually don't — they aren't triglycerides. Add an oil, fat or butter "
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
        return "Soap properties may be incomplete — \(list) \(verb) no fatty-acid data, "
            + "so this breakdown may be inaccurate."
    }
}
