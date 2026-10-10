import SwiftUI

/// A screen with nothing to show: a glyph in `inkFaint`, a New York title in
/// `ink`, and one sentence in `inkSoft`, centred in the space it is given.
///
/// Not a `ContentUnavailableView`: that draws its title in its own font and
/// ignores a serif design set on the text inside it.
struct HoneyLedgerEmptyState: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: LocalizedStringKey

    init(_ title: LocalizedStringKey, systemImage: String, description: LocalizedStringKey) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(Color.inkFaint)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(Color.ink)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(Color.inkSoft)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
