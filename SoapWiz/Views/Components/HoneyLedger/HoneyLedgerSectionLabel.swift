import SwiftUI

/// A list section's header: the title in small tracked capitals, then a
/// hairline running to the trailing edge. A non-nil `isExpanded` adds a
/// trailing chevron that turns as the section folds.
struct HoneyLedgerSectionLabel: View {
    let title: String
    var isExpanded: Bool?

    init(_ title: String, isExpanded: Bool? = nil) {
        self.title = title
        self.isExpanded = isExpanded
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.9)
                .foregroundStyle(Color.inkSoft)
                .layoutPriority(1)
            Rectangle()
                .fill(Color.rule)
                .frame(height: 1)
            if let isExpanded {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.inkFaint)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
        }
        .textCase(nil)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(accessibilityStateLabel)
    }

    private var accessibilityStateLabel: String {
        switch isExpanded {
        case .none: ""
        case .some(true): String(localized: "Expanded")
        case .some(false): String(localized: "Collapsed")
        }
    }
}
