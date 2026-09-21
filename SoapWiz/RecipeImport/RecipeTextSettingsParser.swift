import Foundation

/// Lye settings stated in recipe text, read without the model.
struct RecipeTextSettings: Equatable {
    var superFat: Double?
    var waterParts: Double?
    var fragrancePercentage: Double?
    var lyeType: String?
    var cfmNeutralizer: CFMNeutralizer?
}

/// Reads superfat, water ratio, fragrance load and lye type from the phrases
/// soap makers write them in.
///
/// These values drive `LyeCalculator`, and the model has been seen taking a
/// setting from the wrong number — the lye weight read as the superfat, a
/// fragrance amount read as the fragrance load. A value found here sits next
/// to its own keyword, so it overrides whatever the model reported.
///
/// Whitespace inside a pattern is horizontal only: a keyword on one line never
/// claims a number from the next.
enum RecipeTextSettingsParser {
    static let superFatRange = 0.0...20.0
    static let waterPartsRange = 0.5...5.0
    static let fragrancePercentageRange = 0.0...15.0

    static let superFatKeyword = #/\b(?:super\h*-?\h*fat(?:ting)?|lye\h+discount|sf)\b/#.ignoresCase()
    static let fragranceKeyword = #/\b(?:fragrances?|scents?|essential\h+oils?|eos?|fos?)\b/#.ignoresCase()

    static func parse(_ text: String) -> RecipeTextSettings {
        RecipeTextSettings(
            superFat: superFat(in: text),
            waterParts: waterParts(in: text),
            fragrancePercentage: fragrancePercentage(in: text),
            lyeType: lyeType(in: text),
            cfmNeutralizer: cfmNeutralizer(in: text)
        )
    }

    // MARK: - Superfat

    static func superFat(in text: String) -> Double? {
        let after = #/\b(?:super\h*-?\h*fat(?:ting)?|lye\h+discount|sf)\b\h*(?:of|at|is|:|=|-|—)?\h*(\d+(?:[.,]\d+)?)/#
        let before = #/(\d+(?:[.,]\d+)?)\h*%\h*(?:super\h*-?\h*fat(?:ting)?|lye\h+discount|sf)\b/#
        let value = earliest([
            text.firstMatch(of: after.ignoresCase()).map { ($0.range.lowerBound, RecipeTextNumbers.decimal($0.output.1)) },
            text.firstMatch(of: before.ignoresCase()).map { ($0.range.lowerBound, RecipeTextNumbers.decimal($0.output.1)) }
        ])
        return value.flatMap { superFatRange.contains($0) ? $0 : nil }
    }

    // MARK: - Water

    static func waterParts(in text: String) -> Double? {
        let waterToLye = #/\bwater\h*(?::|\/|to)\h*lye(?:\h+ratio)?\h*(?:of|is|:|=|-)?\h*(\d+(?:[.,]\d+)?)\h*:\h*(\d+(?:[.,]\d+)?)/#
        let lyeToWater = #/\blye\h*(?::|\/|to)\h*water(?:\h+ratio)?\h*(?:of|is|:|=|-)?\h*(\d+(?:[.,]\d+)?)\h*:\h*(\d+(?:[.,]\d+)?)/#
        let ratioFirst = #/(\d+(?:[.,]\d+)?)\h*:\h*(\d+(?:[.,]\d+)?)\h*water\h*(?::|\/|to)\h*lye\b/#
        let timesLye = #/\bwater(?:\h+ratio)?\h*(?::|=|-|is)?\h*(\d+(?:[.,]\d+)?)\h*(?:x|×|times)\h*(?:the\h+)?lye\b/#
        let ratio = #/\bwater\h+ratio\h*(?::|=|of|is)?\h*(\d+(?:[.,]\d+)?)(?!\h*[:%\d])/#
        let concentration = #/\blye\h+(?:concentration|solution(?:\h+strength)?)\h*(?:of|at|is|:|=|-)?\h*(\d+(?:[.,]\d+)?)\h*%/#
        let concentrationFirst = #/(\d+(?:[.,]\d+)?)\h*%\h*lye\h+(?:concentration|solution)\b/#

        let value = earliest([
            text.firstMatch(of: waterToLye.ignoresCase()).map { ($0.range.lowerBound, parts($0.output.1, per: $0.output.2)) },
            text.firstMatch(of: lyeToWater.ignoresCase()).map { ($0.range.lowerBound, parts($0.output.2, per: $0.output.1)) },
            text.firstMatch(of: ratioFirst.ignoresCase()).map { ($0.range.lowerBound, parts($0.output.1, per: $0.output.2)) },
            text.firstMatch(of: timesLye.ignoresCase()).map { ($0.range.lowerBound, RecipeTextNumbers.decimal($0.output.1)) },
            text.firstMatch(of: ratio.ignoresCase()).map { ($0.range.lowerBound, RecipeTextNumbers.decimal($0.output.1)) },
            text.firstMatch(of: concentration.ignoresCase()).map { ($0.range.lowerBound, partsFromConcentration($0.output.1)) },
            text.firstMatch(of: concentrationFirst.ignoresCase()).map { ($0.range.lowerBound, partsFromConcentration($0.output.1)) }
        ])
        return value.flatMap { waterPartsRange.contains($0) ? $0 : nil }
    }

    private static func parts(_ water: Substring, per lye: Substring) -> Double? {
        guard let water = RecipeTextNumbers.decimal(water), let lye = RecipeTextNumbers.decimal(lye), lye > 0 else {
            return nil
        }
        return water / lye
    }

    /// A 33% lye concentration is 33 parts lye in 100 of solution, so 67 parts
    /// water to 33 of lye.
    private static func partsFromConcentration(_ token: Substring) -> Double? {
        guard let concentration = RecipeTextNumbers.decimal(token), concentration > 0, concentration < 100 else {
            return nil
        }
        return (100 - concentration) / concentration
    }

    // MARK: - Fragrance

    /// Only the generic wording counts here. "Lavender EO 2%, Tea Tree EO 1%"
    /// is two rows adding up to a load of 3%, and taking the first as the load
    /// would be wrong; those are left to the model and checked for proximity.
    static func fragrancePercentage(in text: String) -> Double? {
        let after = #/\b(?:fragrance|scent)(?:\h+load)?\h*(?:of|at|is|:|=|-|—)?\h*(\d+(?:[.,]\d+)?)\h*%/#
        let before = #/(\d+(?:[.,]\d+)?)\h*%\h*(?:fragrance|scent)\b/#
        let value = earliest([
            text.firstMatch(of: after.ignoresCase()).map { ($0.range.lowerBound, RecipeTextNumbers.decimal($0.output.1)) },
            text.firstMatch(of: before.ignoresCase()).map { ($0.range.lowerBound, RecipeTextNumbers.decimal($0.output.1)) }
        ])
        return value.flatMap { fragrancePercentageRange.contains($0) ? $0 : nil }
    }

    // MARK: - Lye type

    /// The lye the text names, when it names only one kind.
    static func lyeType(in text: String) -> String? {
        let namesSodium = text.contains(ImportedIngredientName.sodiumLye)
        let namesPotassium = text.contains(ImportedIngredientName.potassiumLye)
        switch (namesSodium, namesPotassium) {
        case (true, false): return "NaOH"
        case (false, true): return "KOH"
        case (true, true), (false, false): return nil
        }
    }

    // MARK: - Failor neutraliser

    /// A number stands beside the neutraliser only in the ingredient list; the
    /// method is a setting the app doses itself, so a naming anywhere in the
    /// text is enough. "Failor" (in "Catherine Failor", "Failor method" or the
    /// possessive "Failor's") and "neutralise the excess lye" both name the
    /// method without naming its neutraliser, and fall back to boric acid, the
    /// app's default. No trailing boundary after "failor": Unicode word
    /// segmentation keeps a possessive apostrophe inside the word, so `failor\b`
    /// would miss "Failor's". Boric acid is tested before borax through
    /// `ImportedIngredientName.failorNeutralizer`.
    static let failorMethodKeyword =
        #/\bfailor|\bneutrali[sz](?:e[sd]?|ing)\h+(?:the\h+)?excess\h+lye\b/#.ignoresCase()

    static func cfmNeutralizer(in text: String) -> CFMNeutralizer? {
        if text.contains(ImportedIngredientName.boricAcid) { return .boricAcid }
        if text.contains(ImportedIngredientName.borax) { return .borax }
        return text.contains(failorMethodKeyword) ? .boricAcid : nil
    }

    // MARK: - Proximity

    /// Whether `value` is written within a few characters of `keyword`.
    ///
    /// The fallback for a setting the patterns above didn't recognise: the
    /// model's value is kept only if the text puts that number beside the
    /// right word. With `requiringPercent`, the number must also carry a `%`.
    static func appears(
        _ value: Double,
        near keyword: some RegexComponent,
        in text: String,
        requiringPercent: Bool
    ) -> Bool {
        let reach = 30
        for match in text.matches(of: keyword) {
            let start = text.index(match.range.lowerBound, offsetBy: -reach, limitedBy: text.startIndex) ?? text.startIndex
            let end = text.index(match.range.upperBound, offsetBy: reach, limitedBy: text.endIndex) ?? text.endIndex
            let window = String(text[start..<end])
            let values = requiringPercent
                ? window.matches(of: #/(\d+(?:[.,]\d+)?)\h*%/#).compactMap { RecipeTextNumbers.decimal($0.output.1) }
                : RecipeTextNumbers.values(in: window)
            if RecipeTextNumbers.contains(value, in: values) { return true }
        }
        return false
    }

    private static func earliest(_ candidates: [(String.Index, Double?)?]) -> Double? {
        candidates
            .compactMap { candidate -> (String.Index, Double)? in
                guard let candidate, let value = candidate.1 else { return nil }
                return (candidate.0, value)
            }
            .min { $0.0 < $1.0 }?
            .1
    }
}
