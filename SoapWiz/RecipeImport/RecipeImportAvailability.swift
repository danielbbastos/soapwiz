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

    /// The sentence under the Settings row.
    ///
    /// This row is now only about the language model, which is the part that
    /// can be unavailable. Importing itself always works: a shared file or a
    /// recipe copied out of SoapWiz is read by plain decoding. So the
    /// unavailable cases explain what is lost rather than implying the feature
    /// is gone.
    ///
    /// It no longer teaches the gesture that reveals import — tapping + on the
    /// Recipes tab shows it, which is what the instruction was compensating for.
    var settingsFooter: String {
        guard !isAvailable else {
            return "Recipes written by hand — pasted, photographed or scanned — are read on this "
                + "device, privately. Tap + on the Recipes tab to import."
        }
        return "\(explanation) Recipes shared from SoapWiz still import exactly, "
            + "as a file or copied text."
    }
}
