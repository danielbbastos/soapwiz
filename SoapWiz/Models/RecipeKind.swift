import Foundation

/// What a recipe makes. A soap recipe runs the lye maths and the fatty-acid
/// derived soap properties; a general recipe — a candle, a balm, a salve — is a
/// plain mixture with the same costing and production and no saponification.
///
/// Surfaced in the form as a single "Non-soap product" toggle rather than a
/// two-value picker, so the default reads as the ordinary case and the
/// alternative as the deliberate one.
enum RecipeKind: String, CaseIterable {
    case soap
    case general

    /// Resolves a stored raw value to a case, defaulting to soap. A recipe
    /// written before the kind existed has no value to read, and every one of
    /// them was a soap recipe.
    static func resolve(_ raw: String) -> RecipeKind {
        RecipeKind(rawValue: raw) ?? .soap
    }
}
