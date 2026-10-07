import SwiftUI

/// Edits the eight fatty acids of an oil's profile, with a live running total.
///
/// Emits rows rather than a `Section`, so the form owns the header; each row
/// draws its own share of the ledger sheet. The total is advisory: real oils
/// carry minor acids this list doesn't track, so a profile that doesn't reach
/// 100 is flagged, never blocked.
struct FattyAcidProfileEditor: View {
    @Binding var profile: FattyAcidProfile

    /// How far from 100 the total may drift before it reads as "check this".
    private let tolerance: Double = 2

    private let acids: [(name: String, keyPath: WritableKeyPath<FattyAcidProfile, Double>)] = [
        ("Lauric", \.lauric),
        ("Myristic", \.myristic),
        ("Palmitic", \.palmitic),
        ("Stearic", \.stearic),
        ("Oleic", \.oleic),
        ("Linoleic", \.linoleic),
        ("Linolenic", \.linolenic),
        ("Ricinoleic", \.ricinoleic)
    ]

    private var totalLooksOff: Bool {
        !profile.isEmpty && abs(profile.total - 100) > tolerance
    }

    /// The acids, then the total.
    private var rowCount: Int { acids.count + 1 }

    var body: some View {
        ForEach(Array(acids.enumerated()), id: \.element.name) { index, acid in
            HoneyLedgerField(acid.name, unit: "%") { focus in
                NumericTextField(
                    prompt: "0", value: binding(for: acid.keyPath), fractionLength: 0...2,
                    width: 80, fillsAvailableWidth: true, focus: focus
                )
            }
            .ledgerSheetRow(position: .position(index: index, count: rowCount))
        }
        let totalColor: Color = totalLooksOff ? .warning : .inkFaint
        VStack(alignment: .leading, spacing: 6) {
            HoneyLedgerLabeledRow("Total", titleColor: .inkFaint) {
                Text.honeyLedgerFigure(
                    profile.total.formatted(percent),
                    unit: "%",
                    numberColor: totalColor,
                    unitColor: totalColor
                )
            }
            if totalLooksOff {
                HoneyLedgerFieldNote(
                    "Profiles usually add up to about 100%. A total far from that gives a less accurate soap-property reading.",
                    tint: .warning
                )
            }
        }
        .ledgerSheetRow(position: .position(index: rowCount - 1, count: rowCount))
    }

    private var percent: FloatingPointFormatStyle<Double> {
        .number.precision(.fractionLength(0...2)).grouping(.never)
    }

    private func binding(for keyPath: WritableKeyPath<FattyAcidProfile, Double>) -> Binding<Double> {
        Binding(
            get: { profile[keyPath: keyPath] },
            set: { profile[keyPath: keyPath] = $0 }
        )
    }
}

#Preview {
    @Previewable @State var profile = FattyAcidProfile(
        palmitic: 3.5, stearic: 3, oleic: 61, linoleic: 20
    )
    Form {
        Section("Fatty-Acid Profile") {
            FattyAcidProfileEditor(profile: $profile)
        }
    }
}
