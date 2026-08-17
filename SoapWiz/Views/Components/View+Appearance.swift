import SwiftUI

// `Color.warmBackground`/`cardBackground`/`warmInk` are generated from Assets.xcassets colorsets.
extension Color {
    /// Row fill marking a selected row in a picker list, tinted enough to read
    /// at a glance over `cardBackground` without competing with the checkmark.
    static var selectedRowBackground: Color { Color.accentColor.opacity(0.18) }
}

extension View {
    func warmBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.warmBackground.ignoresSafeArea())
    }

    // Keep `.navigationTitle` alongside this so back buttons and accessibility still get the plain string.
    ///
    /// Set `overPhoto` on a screen whose content runs up behind the navigation
    /// bar. The warm ink is chosen to read on the app's own background and has
    /// no contrast to fall back on over a photograph — over a pale one it
    /// disappears — so the title turns white and carries a shadow instead,
    /// which reads over a dark photo and a light one alike.
    func warmNavigationTitle(_ title: String, overPhoto: Bool = false) -> some View {
        self.toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(overPhoto ? Color.white : Color.warmInk)
                    .shadow(color: .black.opacity(overPhoto ? 0.45 : 0), radius: 5, y: 1)
            }
        }
    }
}
