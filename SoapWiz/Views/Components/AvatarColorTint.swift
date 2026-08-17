import SwiftUI

extension AvatarColor {
    /// The hue the avatar is built from. System colours rather than fixed
    /// values, so each one adapts between light and dark appearance.
    ///
    /// Never used at full strength behind a letter — see `fill` and `ink`.
    var tint: Color {
        switch self {
        case .red:    .red
        case .orange: .orange
        case .brown:  .brown
        case .green:  .green
        case .teal:   .teal
        case .blue:   .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink:   .pink
        }
    }

    /// The well behind the initial: the hue at low strength, which reads as a
    /// pastel over the card it sits on and as a muted wash in dark appearance.
    ///
    /// A list of avatars at full saturation is a row of traffic lights — it
    /// pulls the eye away from the names, which are what the user is actually
    /// reading, and fights the app's warm, muted palette. Drawn from the same
    /// system colour as `ink` rather than from a second hand-picked set, so the
    /// two can never drift apart.
    var fill: Color { tint.opacity(0.14) }

    /// The initial itself: the hue pulled a third of the way towards the app's
    /// own ink.
    ///
    /// The pure system colour reads as a saturated dot at this size — nine of
    /// them down a list is a row of highlighter pens. Muting it towards the
    /// brown the rest of the app is set in keeps each avatar distinguishable
    /// while letting the names stay the loudest thing on the screen, and still
    /// leaves the letter dark enough to carry the contrast the fill gave up.
    var ink: Color { tint.mix(with: Color.warmInk, by: 0.35) }
}
