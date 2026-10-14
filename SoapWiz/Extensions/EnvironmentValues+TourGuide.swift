import SwiftUI

extension EnvironmentValues {
    /// The guide running the onboarding tour, nil everywhere else. The overlay
    /// hosts, the recipe form and its Ingredients tab follow it when it is set.
    @Entry var tourGuide: TourGuide?
}
