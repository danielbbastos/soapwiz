import SwiftUI

/// The design system's Primary button: a full-width amber capsule with an
/// enamel finish. The label is `onAmber`, not white, which is only about 3:1
/// on amber. Pressing nudges it down a point and softens its shadow; the fill
/// never darkens.
struct HoneyLedgerPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoneyLedgerPrimaryButtonBody(configuration: configuration)
    }
}

private struct HoneyLedgerPrimaryButtonBody: View {
    @Environment(\.isEnabled) private var isEnabled
    let configuration: ButtonStyleConfiguration

    private var fill: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .amberBright, location: 0),
                .init(color: Color.amberBright.mix(with: .amber, by: 0.5), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        let isPressed = configuration.isPressed
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.onAmber)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(fill, in: .capsule)
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(isPressed ? 0.2 : 0.35), lineWidth: 1)
                    .mask(alignment: .top) { Rectangle().frame(height: 6) }
            }
            .overlay {
                Capsule()
                    .strokeBorder(.black.opacity(isPressed ? 0.18 : 0.3), lineWidth: 1)
                    .mask(alignment: .bottom) { Rectangle().frame(height: 6) }
            }
            .shadow(color: Color.shadow.opacity(isPressed ? 0.12 : 0.25), radius: 1, y: 1)
            .offset(y: isPressed ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(.capsule)
    }
}

extension ButtonStyle where Self == HoneyLedgerPrimaryButtonStyle {
    static var honeyLedgerPrimary: HoneyLedgerPrimaryButtonStyle { HoneyLedgerPrimaryButtonStyle() }
}
