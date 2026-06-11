import SwiftUI

/// A small info icon that reveals a short explanatory popover when tapped.
struct InfoPopoverIcon: View {
    let text: String
    var systemImage: String = "info.circle"

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: systemImage)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: 260)
                .presentationCompactAdaptation(.popover)
        }
    }
}
