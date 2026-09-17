import Foundation

/// What an ingredient name written in a recipe turns out to be, and the
/// spellings it can be looked up under.
enum ImportedIngredientName {
    private static let waterNames: Set<String> = [
        "water", "distilled water", "deionized water", "deionised water", "demineralized water",
        "demineralised water", "purified water", "tap water", "spring water", "aqua"
    ]

    private static let settingPrefixes = [
        "superfat", "super fat", "lye discount", "water ratio", "water:lye", "water to lye",
        "lye:water", "lye to water", "lye concentration", "fragrance load"
    ]

    static let sodiumLye = #/\b(?:naoh|sodium\h+hydroxide|caustic\h+soda)\b/#.ignoresCase()
    static let potassiumLye = #/\b(?:koh|potassium\h+hydroxide|caustic\h+potash)\b/#.ignoresCase()
    private static let lyeWord = #/\blye\b/#.ignoresCase()

    private static let fragranceWording = #/\b(?:(?:essential|fragrance)\h+oils?|eos?|fos?|absolutes?)\b/#.ignoresCase()
    private static let oilWording = #/\b(?:oils?|butters?|wax(?:es)?|tallow|lard)\b/#.ignoresCase()
    private static let additiveWords: Set<String> = [
        "clay", "clays", "salt", "salts", "sugar", "sugars", "honey", "oatmeal", "oats", "charcoal",
        "lactate", "citrate", "citric", "silk", "mica", "micas", "colorant", "colorants", "colourant",
        "colourants", "oxide", "oxides", "ultramarine", "ultramarines", "pumice", "spirulina", "milk",
        "yogurt", "yoghurt", "glycerin", "glycerine"
    ]

    /// A lye, which a recipe calculates from its oils rather than lists.
    ///
    /// Reported in the oils it would be counted as an oil and throw the lye
    /// weight off, so it never becomes a row. The recipe's own lye ingredient
    /// setting is where it belongs.
    static func isLye(_ name: String) -> Bool {
        if lyeType(ofLye: name) != nil || name.contains(lyeWord) { return true }
        return IngredientLibrary.entry(matching: withoutParentheticals(name))?.category == IngredientCategory.Name.lyes
    }

    /// "NaOH" or "KOH" for a lye name that says which, otherwise `nil`.
    static func lyeType(ofLye name: String) -> String? {
        if name.contains(sodiumLye) { return "NaOH" }
        if name.contains(potassiumLye) { return "KOH" }
        return nil
    }

    /// Plain water, which the recipe derives from its water ratio. Rose water
    /// and other waters that are really additives don't count.
    static func isWater(_ name: String) -> Bool {
        waterNames.contains(withoutParentheticals(name).lookupKey)
    }

    /// A lye setting reported as though it were an ingredient, such as
    /// "Superfat 3%".
    static func isSetting(_ name: String) -> Bool {
        let key = name.lookupKey
        return settingPrefixes.contains { key.hasPrefix($0) }
    }

    /// The section a name plainly belongs to, or `nil` when the name doesn't say.
    ///
    /// Used for rows that match nothing in the inventory, which otherwise sit
    /// wherever the model put them, and the model has placed "Clay" under
    /// Additives on one run and Oils on the next. Fragrance wording is checked
    /// first, so "Oatmeal Milk & Honey Fragrance Oil" stays a fragrance, and an
    /// oil, butter or wax keeps the model's section, so "Milk Thistle Oil" is
    /// not taken for an additive.
    static func evidentRole(of name: String) -> RecipeIngredientRole? {
        if name.contains(fragranceWording) { return .fragrance }
        if name.contains(oilWording) { return nil }
        let words = name.lookupKey.split { !$0.isLetter }.map(String.init)
        if words.contains(where: additiveWords.contains) { return .additive }
        return nil
    }

    /// The name without notes in brackets: "Palm Oil (RSPO)" → "Palm Oil".
    static func withoutParentheticals(_ name: String) -> String {
        name.replacing(#/\h*[(\[][^)\]]*[)\]]/#, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The spellings to look `name` up under, most literal first.
    ///
    /// Each is still matched exactly. These undo the ways a recipe shortens a
    /// name — a note in brackets, "EO" for essential oil, "castor" for castor
    /// oil — without ever treating two different names as alike, and the review
    /// screen shows the name as written beside whatever it matched.
    ///
    /// "Oil" is appended only for a row listed among the oils. Elsewhere the
    /// suffix would promote a fragrance written as "Coconut" to Coconut Oil,
    /// and matching moves a row into its ingredient's section — into the lye
    /// calculation.
    static func lookupCandidates(for name: String, listedAsOil: Bool) -> [String] {
        let stripped = withoutParentheticals(name)
        let expanded = stripped
            .replacing(#/\beo\b/#.ignoresCase(), with: "Essential Oil")
            .replacing(#/\bfo\b/#.ignoresCase(), with: "Fragrance Oil")
        var candidates = [name, stripped, expanded]
        let expandedKey = expanded.lookupKey
        if listedAsOil, !expandedKey.hasSuffix("oil"), !ImportedIngredient.sectionWords.contains(expandedKey) {
            candidates.append(expanded + " Oil")
        }

        var seen: Set<String> = []
        return candidates.filter { candidate in
            let key = candidate.lookupKey
            return !key.isEmpty && seen.insert(key).inserted
        }
    }
}
