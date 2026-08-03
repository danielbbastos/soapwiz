import Foundation
import FoundationModels

/// Whether recipe import can be offered at all.
///
/// The entry point is hidden rather than disabled when the answer is no: a
/// feature that fails on tap is worse than a feature that isn't there. The
/// reasons are kept apart because they call for different words — "turn on
/// Apple Intelligence" is actionable, "this iPhone can't" is not.
enum RecipeImportAvailability {
    case available
    case appleIntelligenceOff
    case deviceNotEligible
    case modelNotReady
    case unsupportedOS

    static var current: RecipeImportAvailability {
        #if DEBUG
        if RecipeImportDebugOverride.isEnabled { return .available }
        #endif
        guard #available(iOS 26, macOS 26, *) else { return .unsupportedOS }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceOff
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            return .deviceNotEligible
        }
    }

    var isAvailable: Bool { self == .available }

    var explanation: String {
        switch self {
        case .available: ""
        case .appleIntelligenceOff: "Turn on Apple Intelligence in Settings to import recipes."
        case .deviceNotEligible: "This device can't run the on-device model recipe import needs."
        case .modelNotReady: "Apple Intelligence is still downloading. Try again shortly."
        case .unsupportedOS: "Recipe import needs iOS 26 or later."
        }
    }

    /// Short status for the Settings row.
    var statusText: String {
        switch self {
        case .available: "Ready"
        case .appleIntelligenceOff: "Apple Intelligence Off"
        case .deviceNotEligible: "Not Supported"
        case .modelNotReady: "Preparing"
        case .unsupportedOS: "Needs iOS 26"
        }
    }

    var statusSymbol: String {
        switch self {
        case .available: "checkmark.circle.fill"
        case .appleIntelligenceOff: "exclamationmark.circle.fill"
        case .modelNotReady: "clock.fill"
        case .deviceNotEligible, .unsupportedOS: "xmark.circle.fill"
        }
    }

    /// Whether the state is something the user can act on, as opposed to a
    /// permanent fact about the device. Drives whether the row reads as a
    /// prompt or as a statement.
    var isActionable: Bool {
        switch self {
        case .appleIntelligenceOff, .modelNotReady: true
        case .available, .deviceNotEligible, .unsupportedOS: false
        }
    }

    /// The sentence under the Settings row. The available case gets one too —
    /// otherwise the only way to learn the feature exists is to find the
    /// long-press that reveals it.
    var settingsFooter: String {
        guard !isAvailable else {
            return "Paste or scan a recipe and it's read on this device, privately. "
                + "Touch and hold + on the Recipes tab to start."
        }
        return explanation
    }
}
