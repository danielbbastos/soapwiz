import SwiftUI

/// A screen with nothing to show: a glyph in `inkFaint`, a New York title in
/// `ink`, and one sentence in `inkSoft`, centred in the space it is given.
///
/// Not a `ContentUnavailableView`: that draws its title in its own font and
/// ignores a serif design set on the text inside it.
struct HoneyLedgerEmptyState<Actions: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: LocalizedStringKey
    let actions: Actions

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        description: LocalizedStringKey,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.actions = actions()
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
            actions
                .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: Actions.self == EmptyView.self ? .combine : .contain)
    }
}

extension HoneyLedgerEmptyState where Actions == EmptyView {
    init(_ title: LocalizedStringKey, systemImage: String, description: LocalizedStringKey) {
        self.init(title, systemImage: systemImage, description: description) { EmptyView() }
    }
}
