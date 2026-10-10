import SwiftUI

/// Draws a row's share of the sheet and lights it while a button in the row
/// is pressed, tinting the whole row at once. The press has to reach the row
/// background, which the list draws apart from the row's content and across
/// its whole width, so the buttons take `HoneyLedgerRowButtonStyle` and it
/// reports back here.
///
/// A button that sets its own style keeps it and doesn't light the row: an
/// inner style wins over this one. Small buttons inside a row, like the
/// favourite star, are `.borderless` for that reason; a whole-row button sets
/// no style of its own.
///
/// A `NavigationLink` row ignores button styles, so with `navigates` the row
/// lights from the tracker instead, once a finger has held still for a moment.
/// The tracker is only installed for those rows.
///
/// A quick tap is over before a list reports it as a press, so the row
/// flashes once its action fires instead: for a button when the button
/// triggers, and for a link when a touch lifts without becoming a scroll.
struct LedgerSheetRowModifier: ViewModifier {
    let position: LedgerSheetPosition
    let isSelected: Bool
    let navigates: Bool

    @State private var isButtonPressed = false
    @State private var isTouchHeld = false
    @State private var flashCount = 0

    /// Long enough to see under the finger as it lifts, short enough that the
    /// row has faded before a pushed screen settles.
    private static let flashDuration: Duration = .milliseconds(150)

    private var isPressed: Bool {
        isButtonPressed || flashCount > 0 || isTouchHeld
    }

    func body(content: Content) -> some View {
        content
            .buttonStyle(HoneyLedgerRowButtonStyle(isPressed: $isButtonPressed, onTrigger: flash))
            .menuStyle(LedgerRowMenuStyle(isPressed: $isButtonPressed))
            .listRowBackground(
                LedgerSheetRowBackground(
                    position: position,
                    isSelected: isSelected,
                    isPressed: isPressed
                )
                .background {
                    if navigates {
                        LedgerRowTouchTracker(
                            onHold: { isTouchHeld = true },
                            onEnd: { isTap in
                                if isTap {
                                    flash()
                                }
                                withAnimation(HoneyLedgerRowButtonStyle.release) {
                                    isTouchHeld = false
                                }
                            }
                        )
                    }
                }
            )
            .listRowSeparatorTint(Color.rule)
    }

    /// Counted rather than a flag, so a second tap during a flash doesn't
    /// have the first one's end put the row out early.
    private func flash() {
        flashCount += 1
        Task {
            try? await Task.sleep(for: Self.flashDuration)
            withAnimation(HoneyLedgerRowButtonStyle.release) {
                flashCount -= 1
            }
        }
    }
}

/// A whole-row button on a ledger sheet: the label as drawn, with no tint or
/// dimming. Its pressed state goes to `isPressed` for the row to light, and
/// `onTrigger` hears each time it fires, so a tap too quick to count as a
/// press still lights the row. The highlight comes on at once and fades when
/// the finger lifts, as a system row's does.
///
/// A primitive style around a plain `Button` of the same role, since only a
/// primitive style sees the action fire; the inner button keeps the press
/// handling, the enabled state and the accessibility of a real one.
struct HoneyLedgerRowButtonStyle: PrimitiveButtonStyle {
    @Binding var isPressed: Bool
    let onTrigger: () -> Void

    static let release: Animation = .easeOut(duration: 0.15)

    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            onTrigger()
            configuration.trigger()
        } label: {
            configuration.label
        }
        .buttonStyle(LedgerRowPressStyle(isPressed: $isPressed))
    }
}

/// A menu row on a ledger sheet: a menu takes a plain button style for its
/// label but not a primitive one, so it gets the press style directly. A menu
/// opens as the finger comes down, so there is no quick tap to flash for.
private struct LedgerRowMenuStyle: MenuStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        Menu(configuration)
            .buttonStyle(LedgerRowPressStyle(isPressed: $isPressed))
    }
}

/// The inner button's style for `HoneyLedgerRowButtonStyle`.
///
/// The label is stretched across the row and hit-tested over all of it, out
/// into the row's padding: a list makes a whole cell tappable only for a
/// button of its default style, and any other style is tapped on its drawn
/// content alone. The cell's own bounds stop the reach at the row's edge.
private struct LedgerRowPressStyle: ButtonStyle {
    @Binding var isPressed: Bool

    /// About a list row's vertical padding, so a tap near the top or bottom
    /// of the row still lands.
    private static let hitOutset: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle().inset(by: -Self.hitOutset))
            .onChange(of: configuration.isPressed) { _, pressed in
                withAnimation(pressed ? nil : HoneyLedgerRowButtonStyle.release) {
                    isPressed = pressed
                }
            }
    }
}
