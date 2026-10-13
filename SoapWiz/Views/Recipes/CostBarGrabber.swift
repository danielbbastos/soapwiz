import SwiftUI

/// The handle at the top of the expanded cost panel. Dragging it up grows the
/// panel; assistive technologies get it as an adjustable element.
struct CostBarGrabber: View {
    /// How far the carousel has been dragged past its default height.
    @Binding var extraHeight: CGFloat
    /// The room between the default height and the upper bound.
    let extraRoom: CGFloat
    @State private var dragStartExtra: CGFloat?

    /// How much of the room above the default height one accessibility step moves.
    private static let adjustmentStep: CGFloat = 0.25

    /// The dragged height as drawn: what was stored, held to the room there is now.
    private var currentExtraHeight: CGFloat { min(extraHeight, extraRoom) }

    /// The hit area is taller than the grabber looks, reaching into the
    /// layout above and below it; it sits over the header so it wins there.
    var body: some View {
        Capsule()
            .fill(Color.inkSoft.opacity(0.5))
            .frame(width: 36, height: 5)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .padding(.vertical, -12)
            .gesture(resizeGesture)
            .zIndex(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Resize cost breakdown")
            .accessibilityValue(resizeValue)
            .accessibilityAdjustableAction { direction in
                let step = extraRoom * Self.adjustmentStep
                switch direction {
                case .increment: setExtraHeight(currentExtraHeight + step)
                case .decrement: setExtraHeight(currentExtraHeight - step)
                @unknown default: break
                }
            }
    }

    private func setExtraHeight(_ proposed: CGFloat) {
        extraHeight = min(max(0, proposed), extraRoom)
    }

    /// Dragging stores the clamped height, never an overshoot, so reversing
    /// direction responds at once. Measured in the global space because the
    /// grabber moves with the panel under the finger.
    private var resizeGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                let start = dragStartExtra ?? currentExtraHeight
                dragStartExtra = start
                setExtraHeight(start - value.translation.height)
            }
            .onEnded { _ in dragStartExtra = nil }
    }

    private var resizeValue: String {
        if currentExtraHeight <= 0 { return String(localized: "Default height") }
        if currentExtraHeight >= extraRoom { return String(localized: "Full height") }
        return String(localized: "Taller")
    }
}
