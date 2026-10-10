import SwiftUI

/// A small info icon that reveals a short explanatory popover when tapped.
struct InfoPopoverIcon: View {
    var title: String?
    let text: String
    var systemImage: String = "info.circle"

    @State private var isPresented = false

    /// The glyph alone is a ~13pt target; this padding makes it reachable
    /// without changing how it looks.
    static let tapPadding: CGFloat = 6

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: systemImage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(Self.tapPadding)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 8) {
                if let title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // A definite width, not a maximum: a popover sizes itself from the
            // content's ideal size, and an unresolved `maxWidth` clips it.
            .frame(width: 260, alignment: .leading)
            .padding(14)
            .fixedSize()
            .presentationCompactAdaptation(.popover)
        }
    }
}
