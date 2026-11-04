import Foundation

/// The success haptic for the first ingredient a user comes to own, played once
/// per device: later 0-to-1 changes (unstarring and starring again, a delete and
/// a re-add, a sync that brings exactly one row) are not the first.
enum FirstOwnedCelebration {
    static let defaultsKey = "celebratedFirstOwnedIngredient"

    static func shouldPlay(old: Int, new: Int, tracksInventory: Bool, alreadyCelebrated: Bool) -> Bool {
        tracksInventory && !alreadyCelebrated && old == 0 && new == 1
    }
}
