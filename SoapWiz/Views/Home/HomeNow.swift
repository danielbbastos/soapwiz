import SwiftUI

extension EnvironmentValues {
    /// Home's current time, refreshed by `HomeView` (always on screen) so a
    /// card that is absent for days doesn't come back with a stale "now".
    @Entry var homeNow: Date = .now
}
