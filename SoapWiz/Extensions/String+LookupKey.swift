import Foundation

extension String {
    /// The key duplicate lookup rows are grouped and matched by: two names that
    /// produce the same key are the same name as far as the user is concerned.
    ///
    /// Folds case, diacritics and full-width forms, trims the ends, and collapses
    /// runs of internal whitespace, so `" Óleos "` and `"oleos"` match.
    ///
    /// The folding is deliberately locale-independent. `Locale.current` would fold
    /// "I" differently under a Turkish locale, and two devices in different regions
    /// would then disagree about whether two synced rows are the same row — which
    /// is exactly the disagreement `DuplicateMerger` exists to avoid.
    var lookupKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
