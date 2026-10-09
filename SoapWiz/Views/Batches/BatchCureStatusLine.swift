import SwiftUI

/// A batch's cure status as a stamp: "Curing" with the time left beside it, or
/// "Ready". Nothing for a batch that doesn't cure. Shared by the history row and
/// the batch's Cure section so the two always say the same thing.
struct BatchCureStatusLine: View {
    let status: CureStatus

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var lineLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    var body: some View {
        switch status {
        case .curing(let remaining, _):
            // The time sits outside the stamp, which carries only the word.
            // Stacked at the accessibility sizes, where beside the stamp it
            // would wrap a few characters at a time.
            lineLayout {
                curingStamp
                remainingText(remaining)
            }
            .accessibilityElement(children: .combine)
        case .ready:
            StatusStamp(word: String(localized: "Ready"), tone: .success, glyph: "checkmark.circle")
                .fixedSize()
        case .none:
            EmptyView()
        }
    }

    private var curingStamp: some View {
        StatusStamp(word: String(localized: "Curing"), tone: .amber, glyph: "clock.arrow.circlepath")
            .fixedSize()
    }

    private func remainingText(_ remaining: CureRemaining) -> some View {
        CureLengthText.remaining(remaining)
            .font(.subheadline)
            .foregroundStyle(Color.inkSoft)
    }
}
