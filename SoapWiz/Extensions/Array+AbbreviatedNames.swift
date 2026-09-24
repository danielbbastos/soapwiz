import Foundation

extension Array where Element == String {
    /// Spells out the first few names and summarises the rest, for alert messages,
    /// which don't scroll: past a handful of names the exact count carries the
    /// information anyway. The overflow form joins manually because
    /// `ListFormatStyle` has no notion of truncation, and appending to its output
    /// would read "A, B, and C and 22 others".
    func abbreviatedList() -> String {
        guard count > Self.maxNamesListed else { return formatted() }
        let remaining = count - Self.maxNamesListed
        let otherWord = remaining == 1 ? "other" : "others"
        return prefix(Self.maxNamesListed).joined(separator: ", ") + " and \(remaining) \(otherWord)"
    }

    /// Computed because a generic type's extension can't hold a stored static.
    private static var maxNamesListed: Int { 3 }
}
