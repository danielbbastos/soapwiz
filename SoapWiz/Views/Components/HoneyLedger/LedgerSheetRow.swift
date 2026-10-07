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

/// One row's share of the ledger sheet: the `paperRaised` fill (honey when
/// selected), with continuous corners where the sheet turns, and the 1pt `rule`
/// edge on the sides and, at the ends of the sheet, the top or bottom.
struct LedgerSheetRowBackground: View {
    let position: LedgerSheetPosition
    let isSelected: Bool

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
            .fill(isSelected ? Color.honey : Color.paperRaised)
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
