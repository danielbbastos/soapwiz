import SwiftUI

extension EnvironmentValues {
    /// True inside the onboarding tour's sandbox. Switches off what would reach
    /// outside it: the lye safety notice (its acknowledgment is the user's, kept
    /// per device), incoming file URLs, and the Settings sections for iCloud,
    /// backup and restore, reminders and recipe import.
    @Entry var isTourSandbox = false
}
