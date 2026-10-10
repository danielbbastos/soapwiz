import SwiftUI

extension AvatarColor {
    /// The hue the avatar is built from: one of the ledger's pigments, each with
    /// its own light and dark value so it holds its contrast on either paper.
    ///
    /// Never used at full strength behind a letter — see `fill` and `ink`.
    var tint: Color {
        switch self {
        case .red:    .pigmentMadder
        case .orange: .pigmentClay
        case .brown:  .pigmentWalnut
        case .green:  .pigmentOlive
        case .teal:   .pigmentVerdigris
        case .blue:   .pigmentWoad
        case .indigo: .pigmentIndigo
        case .purple: .pigmentFig
        case .pink:   .pigmentRose
        }
    }

    /// The well behind the initial: the pigment at low strength, which reads as
    /// a pale wash over the paper it sits on.
    ///
    /// A list of avatars at full saturation is a row of traffic lights — it
    /// pulls the eye away from the names, which are what the user is actually
    /// reading. Drawn from the same colour as `ink` rather than from a second
    /// hand-picked set, so the two can never drift apart.
    var fill: Color { tint.opacity(0.16) }

    /// The initial itself: the pigment at full strength. The pigments are
    /// already dark enough in light appearance, and light enough in dark, to
    /// carry the contrast the wash gave up.
    var ink: Color { tint }
}
