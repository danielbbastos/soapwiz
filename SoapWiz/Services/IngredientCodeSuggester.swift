import Foundation

/// Suggests a short journal code for an ingredient name — the `<CODE>` in a
/// purchase's `<CODE>-001` journal number.
///
/// Multi-word names take their initials, extended from the last word until they
/// reach three characters or stop colliding; single words take their first three
/// characters, extended the same way. Diacritics are folded first so the code is
/// plain ASCII. Shared by the ingredient form, the library installer's
/// collision handling and the code backfill, so the three can never disagree
/// about what code a name earns.
enum IngredientCodeSuggester {
    static func suggest(for name: String, existingCodes: [String]) -> String {
        let normalised = existingCodes.map { $0.uppercased() }
        let stripped = name.applyingTransform(.stripDiacritics, reverse: false) ?? name
        let words = stripped.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return "" }

        if words.count > 1 {
            let initials = words.map { String($0.prefix(1)).uppercased() }.joined()
            var candidate = initials
            for character in (words.last?.uppercased() ?? "").dropFirst() {
                if candidate.count >= 3 && !normalised.contains(candidate) { return candidate }
                guard candidate.count < 6 else { break }
                candidate.append(character)
            }
            return candidate
        } else {
            // Single word — take first 3 chars, extend if not unique
            let upper = words[0].uppercased()
            for length in 3...6 {
                guard length <= upper.count else { break }
                let candidate = String(upper.prefix(length))
                if !normalised.contains(candidate) { return candidate }
            }
            // Return best-effort (may still conflict if word is very short)
            return String(upper.prefix(min(6, upper.count)))
        }
    }

    /// The code a library entry should install with, given the codes already in
    /// use in the store: the entry's own when it is still free, a freshly
    /// suggested one when a user-created ingredient already took it, or none at
    /// all rather than a duplicate — `IngredientFormView` refuses a repeated
    /// code, so the installer must never create one. `usedCodes` are compared
    /// case-insensitively and must be uppercased by the caller.
    static func installCode(for entry: IngredientLibraryEntry, usedCodes: Set<String>) -> String {
        guard !entry.code.isEmpty else { return "" }
        if !usedCodes.contains(entry.code.uppercased()) { return entry.code }
        let suggested = suggest(for: entry.name, existingCodes: Array(usedCodes))
        guard !suggested.isEmpty, !usedCodes.contains(suggested.uppercased()) else { return "" }
        return suggested
    }
}
