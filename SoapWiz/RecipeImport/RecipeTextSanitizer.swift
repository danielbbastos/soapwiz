import Foundation

/// Turns an arbitrary paste into something that fits the on-device model's
/// context window.
///
/// The window is 4,096 tokens and it is cumulative across instructions, schema,
/// prompt and answer, so a blog post pasted whole — preamble, sidebar, comment
/// section — will not fit. Rather than truncating from the top and hoping the
/// recipe was near the start, this scores each line for how much it looks like
/// a recipe and keeps the densest run that fits the budget. The personal story
/// falls away; the ingredient list survives.
enum RecipeTextSanitizer {
    /// Roughly 1,500 tokens, leaving the rest of the 4,096 for the instructions,
    /// the generation schema and the model's answer. Deliberately conservative:
    /// overshooting costs a failed extraction, undershooting costs a little
    /// context the user can restore by pasting a tighter excerpt.
    static let defaultCharacterBudget = 6_000

    /// Long unbroken prose is split at word boundaries into pieces this size so
    /// the windowing has something to select between. Without it a whole
    /// article pasted as one paragraph is a single line that either fits or
    /// doesn't.
    private static let maximumLineLength = 400

    static func sanitize(
        _ raw: String,
        knownIngredientNames: [String] = [],
        characterBudget: Int = defaultCharacterBudget
    ) -> SanitizedRecipeText {
        let originalLength = raw.count
        let plain = RecipeTextMarkupStripper.stripMarkup(raw)
        let lines = cleanedLines(from: plain)

        guard !lines.isEmpty else {
            return SanitizedRecipeText(text: "", originalLength: originalLength, wasTrimmed: originalLength > 0)
        }

        let vocabulary = oilVocabulary(addingNames: knownIngredientNames)
        let scores = lines.map { score($0, vocabulary: vocabulary) }
        let kept = densestWindow(of: lines, scores: scores, characterBudget: characterBudget)
        let text = kept.joined(separator: "\n")

        return SanitizedRecipeText(
            text: text,
            originalLength: originalLength,
            wasTrimmed: kept.count < lines.count
        )
    }

    /// A light tidy for text about to be shown in the editable box, as opposed
    /// to the aggressive selection done before sending to the model.
    ///
    /// Only removes what the user cannot see anyway: trailing spaces, leading
    /// and trailing blank lines, and runs of more than one blank line. OCR
    /// returns plenty of all three, and they read as unexplained dead space at
    /// the bottom of the box.
    static func tidiedForEditing(_ raw: String) -> String {
        raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .reduce(into: [String]()) { lines, line in
                if line.isEmpty, lines.last?.isEmpty ?? true { return }
                lines.append(line)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Line cleanup

    /// Splits into lines, drops page furniture and blank runs, and breaks up
    /// paragraphs too long to window over.
    static func cleanedLines(from text: String) -> [String] {
        var result: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let withoutURLs = RecipeTextMarkupStripper.removeURLs(rawLine)
            let collapsed = collapseWhitespace(withoutURLs)
            guard !collapsed.isEmpty else { continue }
            guard !RecipeTextMarkupStripper.isBoilerplate(collapsed) else { continue }
            // The exact payload "Copy Recipe" appends is meaningless to the
            // language model and would spend a sixth of the character budget on
            // base64. Text only reaches here when the payload was absent or
            // unreadable, so dropping it costs nothing and leaves the whole
            // budget for the recipe a person can read.
            guard !RecipeTransferMarker.isMarkerLine(collapsed) else { continue }
            result.append(contentsOf: splitLongLine(collapsed))
        }
        return result
    }

    private static func collapseWhitespace(_ line: String) -> String {
        line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func splitLongLine(_ line: String) -> [String] {
        guard line.count > maximumLineLength else { return [line] }
        var pieces: [String] = []
        var current = ""
        for word in line.split(separator: " ") {
            if current.count + word.count + 1 > maximumLineLength, !current.isEmpty {
                pieces.append(current)
                current = ""
            }
            current += current.isEmpty ? String(word) : " \(word)"
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    // MARK: - Scoring

    /// How much a line looks like part of a recipe rather than part of a story.
    ///
    /// A quantity with a unit is the strongest signal, a configuration keyword
    /// nearly as strong, and a recognised oil name — including the user's own
    /// inventory names — pulls in ingredient lines that give no unit at all.
    static func score(_ line: String, vocabulary: Set<String>) -> Int {
        let lowered = line.lowercased()
        var score = 0
        if matches(lowered, pattern: quantityPattern) { score += 3 }
        if configurationKeywords.contains(where: lowered.contains) { score += 3 }
        if vocabulary.contains(where: lowered.contains) { score += 2 }
        if lowered.rangeOfCharacter(from: .decimalDigits) != nil { score += 1 }
        return score
    }

    /// The user's own ingredient names matter more than any builtin list: they
    /// are exactly the oils this user works with, spelled the way they spell
    /// them. Short names are dropped — a two-letter name matches everywhere.
    static func oilVocabulary(addingNames names: [String]) -> Set<String> {
        var vocabulary = builtinOilWords
        for name in names {
            let lowered = name.lowercased().trimmingCharacters(in: .whitespaces)
            if lowered.count >= 4 { vocabulary.insert(lowered) }
        }
        return vocabulary
    }

    private static func matches(_ text: String, pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Windowing

    /// The highest-scoring contiguous run of lines that fits the budget.
    ///
    /// Contiguous rather than cherry-picked: a recipe is a block, and pulling
    /// scattered high-scoring lines out of order would hand the model a list
    /// with no structure left to read.
    static func densestWindow(of lines: [String], scores: [Int], characterBudget: Int) -> [String] {
        guard !lines.isEmpty else { return [] }
        let lengths = lines.map { $0.count + 1 }
        if lengths.reduce(0, +) <= characterBudget { return lines }

        var bestRange = 0..<0
        var bestScore = -1
        var windowScore = 0
        var windowLength = 0
        var start = 0

        for end in lines.indices {
            windowScore += scores[end]
            windowLength += lengths[end]
            while windowLength > characterBudget, start <= end {
                windowScore -= scores[start]
                windowLength -= lengths[start]
                start += 1
            }
            if start <= end, windowScore > bestScore {
                bestScore = windowScore
                bestRange = start..<(end + 1)
            }
        }

        guard !bestRange.isEmpty else { return [truncate(lines[0], to: characterBudget)] }
        return Array(lines[bestRange])
    }

    /// Last resort for a single line longer than the whole budget: cut at the
    /// last word boundary that fits.
    private static func truncate(_ line: String, to budget: Int) -> String {
        guard line.count > budget else { return line }
        let clipped = String(line.prefix(budget))
        guard let lastSpace = clipped.lastIndex(of: " ") else { return clipped }
        return String(clipped[clipped.startIndex..<lastSpace])
    }

    // MARK: - Vocabulary

    private static let quantityPattern =
        "[0-9]+(?:[.,][0-9]+)?\\s*(?:%|g|gr|gram|grams|kg|oz|ounce|ounces|lb|lbs|pound|pounds|ml|l|liter|litre|litres|liters)\\b"

    private static let configurationKeywords = [
        "superfat", "super fat", "lye discount", "lye concentration", "water:lye",
        "water : lye", "water to lye", "lye", "naoh", "koh", "sodium hydroxide",
        "potassium hydroxide", "distilled water", "fragrance oil", "essential oil",
        "total oil", "oil weight", "batch size", "fragrance load"
    ]

    private static let builtinOilWords: Set<String> = [
        "olive", "coconut", "palm", "castor", "shea", "cocoa butter", "mango butter",
        "sunflower", "safflower", "sweet almond", "avocado", "rice bran", "canola",
        "rapeseed", "soybean", "jojoba", "hemp", "grapeseed", "apricot kernel",
        "macadamia", "babassu", "neem", "argan", "sesame", "walnut", "wheat germ",
        "kokum", "illipe", "murumuru", "tucuma", "beeswax", "lard", "tallow",
        "emu oil", "goat milk", "shortening", "peanut", "pumpkin seed", "black seed",
        "camellia", "meadowfoam", "moringa", "sal butter", "stearic acid", "lanolin"
    ]
}
