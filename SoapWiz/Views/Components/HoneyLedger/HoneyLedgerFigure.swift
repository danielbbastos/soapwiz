import SwiftUI

extension Text {
    /// A figure and its unit: the number in `ink` (or `numberColor`), medium
    /// weight with monospaced digits, and the unit after it in `inkSoft`.
    static func honeyLedgerFigure(
        _ number: String,
        unit: String? = nil,
        numberColor: Color = .ink,
        unitColor: Color = .inkSoft
    ) -> Text {
        let figure = Text(number).foregroundStyle(numberColor)
        let text: Text
        if let unit, !unit.isEmpty {
            text = figure + Text(" \(unit)").foregroundStyle(unitColor)
        } else {
            text = figure
        }
        return text.font(.body.weight(.medium)).monospacedDigit()
    }
}
