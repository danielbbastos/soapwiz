import SwiftUI

/// A batch's cure status as a stamp: "Curing" with the time left beside it, or
/// the inked stamp once the cure is over. Nothing for a batch that doesn't cure.
/// Shared by the history row, where the inked stamp reads "Ready", and the
/// batch's Cure section, which passes "Cured" as `readyWord`.
struct BatchCureStatusLine: View {
    let status: CureStatus
    var readyWord = String(localized: "Ready")

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
            // Inked, so the end of the cure stands out. Vertical room so the
            // stamp's tilt isn't clipped by the row.
            StatusStamp(word: readyWord, tone: .success, glyph: "checkmark.circle", isInked: true)
                .fixedSize()
                .padding(.vertical, 3)
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
