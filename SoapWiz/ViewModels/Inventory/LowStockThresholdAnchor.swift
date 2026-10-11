import Foundation

/// What the ingredient form's low-stock field converts from when a unit is
/// picked: the text and the unit it was last typed or stored in.
///
/// Converting from this anchor, rather than from the previous pick, keeps the
/// threshold on the same stored-to-final rule that save applies to stock.
/// Stepping through a unit that can't convert (g, then ml, then L) must not
/// convert the threshold when the stock stays put, and repeated picks don't
/// accumulate rounding. All of it is per form session; nothing is stored.
struct LowStockThresholdAnchor {
    private var text: String
    private var unit: IngredientUnit?

    /// The text the last pick wrote into the field. A field that differs from it
    /// has been typed into since, which is what re-anchors the threshold.
    private var shownText: String

    init(text: String, unit: IngredientUnit?) {
        self.text = text
        self.unit = unit
        self.shownText = text
    }

    /// The threshold as shown in the field. Used both when the form opens and when
    /// a unit change rewrites it, so the two can't drift: a converted value such as
    /// 1.234 kg must survive reopening the form and saving, not be rounded to 1.23.
    ///
    /// The fraction digits run to six so that a round trip (1.234 kg to 1234 g and
    /// back) lands on the text it started from.
    static func displayText(_ value: Double, locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(0...6)).grouping(.never).locale(locale))
    }

    /// The text the field should show once `newUnit` is picked over `oldUnit`.
    ///
    /// If `current` is not what the last pick wrote, the user typed a new value
    /// since, and it becomes the anchor in the unit it was typed in. When the
    /// anchor can't be converted into `newUnit` (blank, unreadable, or a different
    /// kind) the anchor text comes back unchanged.
    mutating func text(
        for newUnit: IngredientUnit?,
        from oldUnit: IngredientUnit?,
        current: String,
        locale: Locale
    ) -> String {
        if current != shownText {
            text = current
            unit = oldUnit
        }
        var result = text
        if let unit, let newUnit, unit != newUnit,
           let value = LocaleDecimal.parse(text, locale: locale),
           let converted = IngredientUnitConverter.convertSameKind(value, from: unit.rawValue, to: newUnit.rawValue) {
            result = Self.displayText(converted, locale: locale)
        }
        shownText = result
        return result
    }
}
