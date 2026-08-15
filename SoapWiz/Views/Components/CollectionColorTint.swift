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
}
