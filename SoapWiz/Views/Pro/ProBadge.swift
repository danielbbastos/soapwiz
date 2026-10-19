import SwiftUI

/// Marks a feature the free version doesn't include. Shown to free users
/// only, so Pro users and the tour's sandbox see no badge.
struct ProBadge: View {
    var body: some View {
        StatusStamp(word: "Pro", tone: .amber)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pro")
    }
}
