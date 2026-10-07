import SwiftUI

extension CollectionColor {
    /// The chip's accent. `neutral` follows the app tint so a collection with no
    /// colour still reads as selectable rather than disabled.
    var tint: Color {
        switch self {
        case .neutral: Color("AccentColor")
        case .red:     .red
        case .orange:  .orange
        case .yellow:  .yellow
        case .green:   .green
        case .teal:    .teal
        case .blue:    .blue
        case .purple:  .purple
        case .pink:    .pink
        }
    }

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
