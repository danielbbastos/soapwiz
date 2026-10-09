import SwiftUI

/// Cure lengths as soap makers say them.
enum CureLengthText {
    /// In weeks, falling back to days for a length that isn't a whole number
    /// of weeks.
    static func text(days: Int) -> Text {
        if days % 7 == 0 {
            Text("^[\(days / 7) week](inflect: true)")
        } else {
            Text("^[\(days) day](inflect: true)")
        }
    }

    /// "12 days left", or "26 weeks left" once the end is over two months away.
    static func remaining(_ remaining: CureRemaining) -> Text {
        switch remaining {
        case .days(let days): Text("^[\(days) day](inflect: true) left")
        case .weeks(let weeks): Text("^[\(weeks) week](inflect: true) left")
        }
    }
}
