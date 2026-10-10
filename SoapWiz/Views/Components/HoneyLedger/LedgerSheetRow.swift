import SwiftUI

/// Where a row sits in a ledger sheet drawn one row at a time. A `List` can't
/// stroke a section, so each row draws its own piece of the sheet's edge and
/// the pieces meet.
enum LedgerSheetPosition: Equatable {
    case only, first, middle, last

    /// A position outside `0..<count` is clamped to the nearest row, and a
    /// `count` below one is a sheet of a single row: a list that is mid-update
    /// may briefly hand a row an index its list no longer has, and a plain
    /// row is a better draw than a trap.
    static func position(index: Int, count: Int) -> LedgerSheetPosition {
        guard count > 1 else { return .only }
        if index <= 0 { return .first }
        if index >= count - 1 { return .last }
        return .middle
    }

    var roundsTop: Bool {
        switch self {
        case .only, .first: true
        case .middle, .last: false
        }
    }

    var roundsBottom: Bool {
        switch self {
        case .only, .last: true
        case .first, .middle: false
        }
    }
}

/// What fills a row of the ledger sheet. Pressed is a honey wash pre-mixed over
/// the raised paper, 35% in light mode and 50% in dark, chosen so the pressed
/// row stands out from a plain one by the same contrast in both. A finger on a
/// row reads as the first step towards selecting it: darker than the paper in
/// light mode and lighter in dark, as the system's own row highlight is. The
/// whole row takes the colour at once. A selected row stays honey while
/// pressed.
enum LedgerSheetRowFill: Equatable {
    case raised, pressed, selected

    init(isSelected: Bool, isPressed: Bool) {
        if isSelected {
            self = .selected
        } else if isPressed {
            self = .pressed
        } else {
            self = .raised
        }
    }

    var color: Color {
        switch self {
        case .raised: Color.paperRaised
        case .pressed: Color.honeyPressed
        case .selected: Color.honey
        }
    }
}

/// One row's share of the ledger sheet: the `paperRaised` fill (honey when
/// selected, pressed honey while pressed), with continuous corners where the
/// sheet turns, and the 1pt `rule` edge on the sides and, at the ends of the
/// sheet, the top or bottom.
struct LedgerSheetRowBackground: View {
    let position: LedgerSheetPosition
    let isSelected: Bool
    var isPressed = false

    private var fill: LedgerSheetRowFill {
        LedgerSheetRowFill(isSelected: isSelected, isPressed: isPressed)
    }

    /// Not the design system's 18pt: the inset-grouped list masks its section
    /// with its own corner radius and clips whatever a row draws outside it,
    /// so a smaller radius here has its corner stroke cut off by that mask. The
    /// mask measures about 24pt on iOS 26 on iPhone; one point more keeps the
    /// whole stroke just inside it.
    private static let radius: CGFloat = 26

    var body: some View {
        let top = position.roundsTop ? Self.radius : 0
        let bottom = position.roundsBottom ? Self.radius : 0
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: top,
            bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom,
            topTrailingRadius: top,
            style: .continuous
        )
        shape
            .fill(fill.color)
            .overlay {
                // The whole outline, grown a point past the row where the sheet
                // doesn't end, so the top or bottom stroke falls outside the
                // row and is clipped away. The sides then run the row's full
                // height and meet the next row's without a notch.
                shape
                    .strokeBorder(Color.rule, lineWidth: 1)
                    .padding(.top, position.roundsTop ? 0 : -1)
                    .padding(.bottom, position.roundsBottom ? 0 : -1)
            }
            .clipShape(Rectangle())
    }
}
