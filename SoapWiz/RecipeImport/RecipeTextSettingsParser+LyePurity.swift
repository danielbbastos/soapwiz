import Foundation

extension RecipeTextSettingsParser {
    // MARK: - Lye purity

    /// The purity written beside a lye: "90% Purity KOH", "KOH (90%)",
    /// "NaOH 99%" or a bare "purity: 90%".
    ///
    /// Only a percentage touching the lye's own name or the word "purity"
    /// counts. "Lye concentration 90%" is a different setting that LyeCalc
    /// prints beside the purity, and neither pattern reaches it.
    ///
    /// A text that names both a sodium and a potassium lye describes a blend or
    /// hybrid, which a single purity can't express, so it reads as none however
    /// the number is worded. A share written beside only one of the lyes, as in
    /// "90% NaOH, KOH for the rest" or "75% NaOH, 90% pure KOH", looks just like
    /// a purity, and one purity applied to two lyes would have the form weigh
    /// more lye than the oils need. Per-lye purities stay readable through
    /// `weightPurity(of:in:)`.
    ///
    /// A bare "100% KOH" or "NaOH 100%" says the lye is the only one in the
    /// recipe, not that it is pure, so a 100 beside the lye's name alone is
    /// ignored. With "pure" or "purity" attached, as in "100% pure NaOH" or
    /// "purity: 100%", it is a purity.
    static func lyePurity(in text: String) -> Double? {
        guard !namesBothLyes(text) else { return nil }

        let before = #/
            (\d+(?:[.,]\d+)?)\h*%\h*((?:pure|purity)\h+)?
            (naoh|koh|sodium\h+hydroxide|potassium\h+hydroxide|caustic\h+(?:soda|potash))\b
            /#.ignoresCase()
        let after = #/
            \b(naoh|koh|sodium\h+hydroxide|potassium\h+hydroxide|caustic\h+(?:soda|potash))
            \h*[:(]?\h*(\d+(?:[.,]\d+)?)\h*%
            /#.ignoresCase()
        let purityFirst = #/\bpurity\h*(?:of|:|=|is)?\h*(\d+(?:[.,]\d+)?)\h*%/#.ignoresCase()

        let found: [StatedPurity] =
            text.matches(of: weightAtPurity).compactMap { match in
                statedPurity(at: match.range, value: purity(match.output.2))
            }
            + text.matches(of: before).compactMap { match in
                let value = match.output.2 == nil ? bareLyePurity(match.output.1) : purity(match.output.1)
                return statedPurity(at: match.range, value: value)
            }
            + text.matches(of: after).compactMap { match in
                statedPurity(at: match.range, value: bareLyePurity(match.output.2))
            }
            + text.matches(of: purityFirst).compactMap { match in
                statedPurity(at: match.range, value: purity(match.output.1))
            }

        return found.min { $0.position < $1.position }?.value
    }

    /// A bare "potash" is counted as a potassium lye here only. As an
    /// ingredient name it is ambiguous (wood ash, potassium carbonate), so it
    /// isn't in `ImportedIngredientName.potassiumLye`; beside "NaOH" in a lye
    /// line, though, it is the potassium lye. "Potassium lye" is also not in
    /// that pattern, which only spells the hydroxide out.
    private static let potassiumLyeWording = #/\b(?:potassium\h+lye|potash)\b/#.ignoresCase()

    private static func namesBothLyes(_ text: String) -> Bool {
        text.contains(ImportedIngredientName.sodiumLye)
            && (text.contains(ImportedIngredientName.potassiumLye) || text.contains(potassiumLyeWording))
    }

    private static func statedPurity(at range: Range<String.Index>, value: Double?) -> StatedPurity? {
        value.map { StatedPurity(position: range.lowerBound, value: $0) }
    }

    private struct StatedPurity {
        let position: String.Index
        let value: Double
    }

    private static func purity(_ token: Substring) -> Double? {
        RecipeTextNumbers.decimal(token).flatMap { lyePurityRange.contains($0) ? $0 : nil }
    }

    /// A purity written beside a lye's name with no "pure" or "purity" word,
    /// where 100 means the only lye rather than a pure one.
    private static func bareLyePurity(_ token: Substring) -> Double? {
        purity(token).flatMap { $0 == 100 ? nil : $0 }
    }

    /// Soapmaking Friend's totals: "NaOH Weight at 99 % Purity 14.67 oz".
    private static let weightAtPurity =
        #/\b(naoh|koh)\h+weight\h+at\h+(\d+(?:[.,]\d+)?)\h*%\h*purity\b/#.ignoresCase()

    /// The purity a text states for one named lye of a hybrid, which
    /// `lyePurity(in:)` leaves unread because a single value can't say which.
    /// Only the "Weight at N % Purity" wording is read, as it names its lye.
    static func weightPurity(of lye: String, in text: String) -> Double? {
        text.matches(of: weightAtPurity)
            .first { ImportedIngredientName.lyeType(ofLye: String($0.output.1)) == lye }
            .flatMap { purity($0.output.2) }
    }

    // MARK: - Dual lye ratio

    private static let sodiumFirstRatio =
        #/\bnaoh\h*\/\h*koh\h+ratio\h*[:=]?\h*(\d+(?:[.,]\d+)?)\h*%?\h*\/\h*(\d+(?:[.,]\d+)?)\h*%?/#.ignoresCase()
    private static let potassiumFirstRatio =
        #/\bkoh\h*\/\h*naoh\h+ratio\h*[:=]?\h*(\d+(?:[.,]\d+)?)\h*%?\h*\/\h*(\d+(?:[.,]\d+)?)\h*%?/#.ignoresCase()

    /// The KOH share of a hybrid lye, from "NaOH / KOH Ratio 25 % / 75 %" or the
    /// same with the lyes in the other order.
    ///
    /// Only when both shares are written and make a whole: a lone share, or two
    /// that don't add to 100, are more likely a misreading than a lye blend.
    static func kohPercentage(in text: String) -> Double? {
        if let match = text.firstMatch(of: sodiumFirstRatio),
           let naoh = RecipeTextNumbers.decimal(match.output.1),
           let koh = RecipeTextNumbers.decimal(match.output.2) {
            return kohShare(naoh: naoh, koh: koh)
        }
        if let match = text.firstMatch(of: potassiumFirstRatio),
           let koh = RecipeTextNumbers.decimal(match.output.1),
           let naoh = RecipeTextNumbers.decimal(match.output.2) {
            return kohShare(naoh: naoh, koh: koh)
        }
        return nil
    }

    private static func kohShare(naoh: Double, koh: Double) -> Double? {
        abs(naoh + koh - 100) <= 0.05 ? koh : nil
    }
}
