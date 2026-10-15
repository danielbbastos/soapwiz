import SwiftUI

extension View {
    /// Opens and closes the recipe form's cost panel as the tour asks for its
    /// steps. Does nothing outside the tour.
    func followsTourCostPanel(_ isExpanded: Binding<Bool>) -> some View {
        modifier(TourCostPanelFollower(isExpanded: isExpanded))
    }
}

private struct TourCostPanelFollower: ViewModifier {
    @Binding var isExpanded: Bool

    @Environment(\.tourGuide) private var guide

    func body(content: Content) -> some View {
        // `initial`, since the Ingredients tab is rebuilt on every tab switch.
        content.onChange(of: guide?.costPanelExpanded ?? false, initial: true) { _, expanded in
            guard guide != nil else { return }
            // The panel's own curve and length, which the spotlight's move to
            // it shares.
            withAnimation(TourMotion.animation) { isExpanded = expanded }
        }
    }
}
