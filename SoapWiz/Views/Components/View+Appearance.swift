import SwiftUI

// `Color.warmBackground`/`cardBackground`/`warmInk` are generated from Assets.xcassets colorsets.
extension View {
    func warmBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.warmBackground.ignoresSafeArea())
    }

    // Keep `.navigationTitle` alongside this so back buttons and accessibility still get the plain string.
    func warmNavigationTitle(_ title: String) -> some View {
        self.toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.warmInk)
            }
        }
    }
}
