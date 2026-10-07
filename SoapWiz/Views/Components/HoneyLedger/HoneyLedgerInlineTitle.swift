import SwiftUI

extension View {
    /// The inline navigation title in New York semibold `ink`, or white with a
    /// shadow over a photograph, where `ink` has no contrast to rely on.
    /// Keep `.navigationTitle` alongside this for the title text itself.
    func honeyLedgerInlineTitle(_ title: String, overPhoto: Bool = false) -> some View {
        toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .fontDesign(.serif)
                    .foregroundStyle(overPhoto ? Color.white : Color.ink)
                    .shadow(color: .black.opacity(overPhoto ? 0.45 : 0), radius: 5, y: 1)
            }
        }
    }
}
