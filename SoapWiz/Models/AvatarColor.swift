import Foundation

/// The colour behind an ingredient's initial when it has no photo.
///
/// A closed set rather than free text, for the same reason `CollectionColor` is
/// one: a stored value always has to resolve to something renderable, and an
/// open palette drifts into colours the letter stops reading against. Kept
/// separate from `CollectionColor` because that palette carries a `neutral` case
/// whose raw value is the empty string, and here the empty string has to mean
/// "not assigned yet" so it can be derived instead.
///
/// Every colour is saturated enough to carry white type. Yellow is deliberately
/// absent for that reason.
enum AvatarColor: String, CaseIterable {
    case red
    case orange
    case brown
    case green
    case teal
    case blue
    case indigo
    case purple
    case pink

    /// Assigned once, when the ingredient is created. Random rather than derived
    /// so two ingredients that start with the same letter usually differ, which
    /// is the whole point of the colour in a list sorted by name.
    static func random() -> AvatarColor {
        allCases.randomElement() ?? .blue
    }

    /// Resolves a stored raw value, falling back to a colour derived from
    /// `fallbackSeed`.
    ///
    /// The fallback covers two cases that must never render colourless: a row
    /// written before this attribute existed, and a row arriving from a device
    /// still on an older build. Deriving beats backfilling — a launch-time pass
    /// over the whole inventory would write, and then sync, a colour for every
    /// ingredient the user owns.
    static func resolve(_ raw: String, fallbackSeed: String) -> AvatarColor {
        AvatarColor(rawValue: raw) ?? derived(from: fallbackSeed)
    }

    /// FNV-1a over the seed's lookup key.
    ///
    /// Hand-rolled rather than `hashValue`: Swift seeds `Hasher` per process, so
    /// the same ingredient would come back a different colour after every launch
    /// — and a colour that changes on its own is worse than no colour at all.
    /// The lookup key folds case and diacritics, so an ingredient renamed from
    /// "olive oil" to "Olive Oil" keeps the colour it had.
    static func derived(from seed: String) -> AvatarColor {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Data(seed.lookupKey.utf8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let index = Int(hash % UInt64(allCases.count))
        return allCases[index]
    }
}
