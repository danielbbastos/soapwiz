import SwiftUI

/// A small info icon that reveals a short explanatory popover when tapped.
struct InfoPopoverIcon: View {
    var title: String?
    let text: String
    var systemImage: String = "info.circle"

    @State private var internalIsPresented = false

    private let externalIsPresented: Binding<Bool>?

    /// The glyph alone is a ~13pt target; this padding makes it reachable
    /// without changing how it looks.
    static let tapPadding: CGFloat = 6

    init(title: String? = nil, text: String, systemImage: String = "info.circle") {
        self.title = title
        self.text = text
        self.systemImage = systemImage
        externalIsPresented = nil
    }

    /// Lets a parent open the popover, for a row that is tappable as a whole.
    init(
        title: String? = nil,
        text: String,
        systemImage: String = "info.circle",
        isPresented: Binding<Bool>
    ) {
        self.title = title
        self.text = text
        self.systemImage = systemImage
        externalIsPresented = isPresented
    }

    private var isPresented: Binding<Bool> {
        externalIsPresented ?? $internalIsPresented
    }

    var body: some View {
        Button {
            isPresented.wrappedValue = true
        } label: {
            Image(systemName: systemImage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(Self.tapPadding)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .popover(isPresented: isPresented) {
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
