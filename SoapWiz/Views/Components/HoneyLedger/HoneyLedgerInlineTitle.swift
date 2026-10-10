import SwiftUI

extension View {
    /// The inline navigation title in New York semibold `ink`, or white with a
    /// shadow over a photograph, where `ink` has no contrast to rely on.
    /// Keep `.navigationTitle` alongside this for the title text itself.
    ///
    /// Before iOS 26 the bar is `paper` once content has scrolled under it, and
    /// clear while a photograph is behind it or a `headerStrip` paints the
    /// paper itself.
    func honeyLedgerInlineTitle(_ title: String, overPhoto: Bool = false) -> some View {
        modifier(HoneyLedgerInlineTitleModifier(title: title, overPhoto: overPhoto))
    }
}

private struct HoneyLedgerInlineTitleModifier: ViewModifier {
    let title: String
    let overPhoto: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let titled = content
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .fontDesign(.serif)
                        .foregroundStyle(overPhoto ? Color.white : Color.ink)
                        .shadow(color: .black.opacity(overPhoto ? 0.45 : 0), radius: 5, y: 1)
                }
            }
        if #available(iOS 26, *) {
            titled
        } else {
            titled.modifier(LegacyInlineBarModifier(overPhoto: overPhoto))
        }
    }
}

/// The inline title's bar background before iOS 26.
private struct LegacyInlineBarModifier: ViewModifier {
    let overPhoto: Bool

    @Environment(\.ledgerHasHeaderStrip) private var stripInside
    @State private var stripOutside = false

    private var background: LedgerNavigationBarBackground {
        overPhoto || stripInside || stripOutside ? .transparent : .paper
    }

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(LedgerHasHeaderStripPreference.self) { hasStrip in
                stripOutside = hasStrip
            }
            .background {
                LedgerInlineBarConfigurator(background: background)
                    .frame(width: 0, height: 0)
            }
    }
}
