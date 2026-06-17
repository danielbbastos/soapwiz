import SwiftUI

/// A tappable section header with a chevron that rotates as the section
/// collapses/expands. Shared by the recipe ingredient sections.
struct CollapsibleSectionHeader: View {
    let title: String
    @Binding var expanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(expanded ? 0 : -90))
                    .animation(.easeInOut(duration: 0.2), value: expanded)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}
