import SwiftUI

/// A tappable `HoneyLedgerSectionLabel` whose chevron turns as the section
/// folds. Shared by the recipe form's ingredient sections.
struct CollapsibleSectionHeader: View {
    let title: String
    @Binding var expanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        } label: {
            HoneyLedgerSectionLabel(title, isExpanded: expanded)
                .animation(.easeInOut(duration: 0.2), value: expanded)
        }
        .buttonStyle(.plain)
    }
}
