import SwiftUI

extension CollectionColor {
    /// The colour drawn for the collection in Settings and pickers, the same
    /// pigment as its chip dot. `neutral` falls back to the app accent so it
    /// still reads as selectable.
    var swatch: Color { pigment ?? Color("AccentColor") }

    /// The ledger's pigment for the collection's dot, nil for `neutral`, which
    /// shows none.
    var pigment: Color? {
        switch self {
        case .neutral: nil
        case .red:     .pigmentMadder
        case .orange:  .pigmentClay
        case .yellow:  .amber
        case .green:   .pigmentOlive
        case .teal:    .pigmentVerdigris
        case .blue:    .pigmentWoad
        case .purple:  .pigmentFig
        case .pink:    .pigmentRose
        }
    }
}
