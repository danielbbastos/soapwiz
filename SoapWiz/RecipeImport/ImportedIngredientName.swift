import Foundation

/// What an ingredient name written in a recipe turns out to be, and the
/// spellings it can be looked up under.
enum ImportedIngredientName {
    private static let waterNames: Set<String> = [
        "water", "distilled water", "deionized water", "deionised water", "demineralized water",
        "demineralised water", "purified water", "tap water", "spring water", "aqua",
        "agua", "agua destilada", "agua desmineralizada"
    ]

    private static let settingPrefixes = [
        "superfat", "super fat", "lye discount", "water ratio", "water:lye", "water to lye",
        "lye:water", "lye to water", "lye concentration", "fragrance load"
    ]

    /// Spanish and Portuguese spellings are included: "sosa" and "potasa" are
    /// the everyday names of the two lyes there. A bare "soda" is not, since it
    /// is also baking soda and soda ash; see `isBareSoda`.
    static let sodiumLye =
        #/
        \b(?:
            naoh
            |sodium\h+hydroxide
            |caustic\h+soda
            |sosa(?:\h+c[aá]ustica)?
            |soda\h+c[aá]ustica
            |hidr[oó]xido\h+de\h+sodio
        )\b
        /#.ignoresCase()
    static let potassiumLye =
        #/\b(?:koh|potassium\h+hydroxide|caustic\h+potash|potasa(?:\h+c[aá]ustica)?|hidr[oó]xido\h+de\h+potasio)\b/#.ignoresCase()
    private static let lyeWord = #/\blye\b/#.ignoresCase()

    static let boricAcid = #/\bboric\h+acid\b/#.ignoresCase()
    static let borax = #/\b(?:borax|sodium\h+borate)\b/#.ignoresCase()

    private static let fragranceWording = #/\b(?:(?:essential|fragrance)\h+oils?|fragrances?|scents?|eos?|fos?|absolutes?)\b/#.ignoresCase()
    private static let oilWording =
        #/\b(?:oils?|butters?|(?:bees)?wax(?:es)?|carnauba|candelilla|tallow|lard|aceites?|mantecas?|ceras?)\b/#.ignoresCase()
    private static let additiveWords: Set<String> = [
        "clay", "clays", "salt", "salts", "sugar", "sugars", "honey", "oatmeal", "oats", "charcoal",
        "lactate", "citrate", "citric", "silk", "mica", "micas", "colorant", "colorants", "colourant",
        "colourants", "oxide", "oxides", "dioxide", "ultramarine", "ultramarines", "pumice", "spirulina", "milk",
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
        if name.contains(sodiumLye) || isBareSoda(name) { return "NaOH" }
        if name.contains(potassiumLye) { return "KOH" }
        return nil
    }

    /// A name that is just "soda", which Spanish recipes write for the sodium
    /// lye ("soda: 99.2"). Only the whole name counts, so "baking soda", "soda
    /// ash" and "bicarbonate of soda" stay ordinary ingredients.
    private static func isBareSoda(_ name: String) -> Bool {
        withoutParentheticals(name).lookupKey == "soda"
    }

    /// Plain water, which the recipe derives from its water ratio. Rose water
    /// and other waters that are really additives don't count.
    static func isWater(_ name: String) -> Bool {
        waterNames.contains(withoutParentheticals(name).lookupKey)
    }

    /// Water followed by a note instead of an amount: "Distilled water for
    /// dilution, as needed". The recipe derives its water from the ratio, and
    /// such a row carries no quantity worth keeping.
    ///
    /// Only the start of the name counts, and the rest must read as a note:
    /// nothing, or wording such as "for", "as needed" or "if", or a bracket,
    /// comma, dash or colon. "Rose Water", "Waterlily Extract", "Water Kefir"
    /// and "Water Soluble Dye" are not taken for plain water.
    static func isWaterWithNote(_ name: String) -> Bool {
        let key = withoutParentheticals(name).lookupKey
        return waterNames.contains { water in
            guard key.hasPrefix(water) else { return false }
            return readsAsNote(key.dropFirst(water.count))
        }
    }

    private static let noteOpeners = ["for", "as needed", "as required", "to", "if"]
    private static let notePunctuation: Set<Character> = [",", "(", "-", ":"]

    private static func readsAsNote(_ rest: Substring) -> Bool {
        let trimmed = rest.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let first = trimmed.first else { return true }
        if notePunctuation.contains(first) { return true }
        return noteOpeners.contains { opener in
            guard trimmed.hasPrefix(opener) else { return false }
            guard let next = trimmed.dropFirst(opener.count).first else { return true }
            return !next.isLetter && !next.isNumber
        }
    }

    /// The Catherine Failor neutraliser a name is, or `nil` when it is neither
    /// borax nor boric acid.
    ///
    /// In a liquid or cream soap these mop up the method's excess lye and belong
    /// on the recipe as a setting rather than a row; in a solid bar they are
    /// ordinary additives. The caller decides which by the recipe's lye and uses
    /// this only to pull the row out once it has. Boric acid is tested first so
    /// "boric acid" is never taken for a bare "borax".
    static func failorNeutralizer(named name: String) -> CFMNeutralizer? {
        let stripped = withoutParentheticals(name)
        if stripped.contains(boricAcid) { return .boricAcid }
        if stripped.contains(borax) { return .borax }
        return nil
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
        if hasOilWording(name) { return nil }
        let words = name.lookupKey.split { !$0.isLetter }.map(String.init)
        if words.contains(where: additiveWords.contains) { return .additive }
        return nil
    }

    /// Whether a name says it is an oil, butter or wax, in English or Spanish.
    ///
    /// `evidentRole` returns `nil` both for such a name and for one that says
    /// nothing, so a caller that must tell them apart asks this.
    static func hasOilWording(_ name: String) -> Bool {
        name.contains(oilWording)
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
