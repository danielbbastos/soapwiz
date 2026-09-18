import SwiftUI

/// Edits the eight fatty acids of an oil's profile, with a live running total.
///
/// Emits rows rather than a `Section`, so the form owns the header and the card
/// background — the same arrangement the recipe stats use for the read-only
/// breakdown. The total is advisory: real oils carry minor acids this list
/// doesn't track, so a profile that doesn't reach 100 is flagged, never blocked.
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

    var body: some View {
        ForEach(acids, id: \.name) { acid in
            HStack {
                Text(acid.name)
                Spacer()
                TextField("0", value: binding(for: acid.keyPath), format: percent)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("%")
                    .foregroundStyle(.secondary)
            }
        }
        HStack {
            Text("Total")
            Spacer()
            Text(profile.total.formatted(percent))
            Text("%")
        }
        .foregroundStyle(totalLooksOff ? Color.orange : .secondary)
        if totalLooksOff {
            Text("Profiles usually add up to about 100%. A total far from that gives a less accurate soap-property reading.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
