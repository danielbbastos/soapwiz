import Foundation

extension RecipeTextSettingsParser {
    // MARK: - Lye purity

    /// The purity written beside a lye: "90% Purity KOH", "KOH (90%)",
    /// "NaOH 99%" or a bare "purity: 90%".
    ///
    /// Only a percentage touching the lye's own name or the word "purity"
    /// counts. "Lye concentration 90%" is a different setting that LyeCalc
    /// prints beside the purity, and neither pattern reaches it. A text that
    /// gives purities for both NaOH and KOH describes a hybrid lye, which a
    /// single purity can't express, so it reads as none.
    static func lyePurity(in text: String) -> Double? {
        let before = #/
            (\d+(?:[.,]\d+)?)\h*%\h*(?:(?:pure|purity)\h+)?
            (naoh|koh|sodium\h+hydroxide|potassium\h+hydroxide|caustic\h+(?:soda|potash))\b
            /#.ignoresCase()
        let after = #/
            \b(naoh|koh|sodium\h+hydroxide|potassium\h+hydroxide|caustic\h+(?:soda|potash))
            \h*[:(]?\h*(\d+(?:[.,]\d+)?)\h*%
            /#.ignoresCase()
        let purityFirst = #/\bpurity\h*(?:of|:|=|is)?\h*(\d+(?:[.,]\d+)?)\h*%/#.ignoresCase()

        let found: [StatedPurity] =
            text.matches(of: weightAtPurity).compactMap { match in
                purity(match.output.2).map {
                    StatedPurity(
                        position: match.range.lowerBound,
                        value: $0,
                        lye: ImportedIngredientName.lyeType(ofLye: String(match.output.1))
                    )
                }
            }
            + text.matches(of: before).compactMap { match in
                purity(match.output.1).map {
                    StatedPurity(
                        position: match.range.lowerBound,
                        value: $0,
                        lye: ImportedIngredientName.lyeType(ofLye: String(match.output.2))
                    )
                }
            }
            + text.matches(of: after).compactMap { match in
                purity(match.output.2).map {
                    StatedPurity(
                        position: match.range.lowerBound,
                        value: $0,
                        lye: ImportedIngredientName.lyeType(ofLye: String(match.output.1))
                    )
                }
            }
            + text.matches(of: purityFirst).compactMap { match in
                purity(match.output.1).map {
                    StatedPurity(position: match.range.lowerBound, value: $0, lye: nil)
                }
            }

        let namedLyes = Set(found.compactMap(\.lye))
        guard namedLyes.count < 2 else { return nil }
        if found.contains(where: { $0.lye == nil }), text.contains(ImportedIngredientName.sodiumLye),
           text.contains(ImportedIngredientName.potassiumLye) {
            return nil
        }
        return found.min { $0.position < $1.position }?.value
    }

    private struct StatedPurity {
        let position: String.Index
        let value: Double
        let lye: String?
    }

    private static func purity(_ token: Substring) -> Double? {
        RecipeTextNumbers.decimal(token).flatMap { lyePurityRange.contains($0) ? $0 : nil }
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
