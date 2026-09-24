import Foundation

/// Reads back the text "Copy Recipe" writes (`RecipeTextExporter.text(for:)`),
/// without the model.
///
/// The model misreads that text badly: it takes the bracketed weight beside an
/// oil's share as the amount, can't parse a space-grouped `1 310,4`, and has no
/// batch total to read, since the copy states one only through those brackets.
/// SoapWiz wrote the text, so its shape is known exactly and every value can be
/// taken from where the exporter put it.
///
/// Recognition is all or nothing. A line the exporter could not have written —
/// a hand edit, a paragraph pasted above it — means the text isn't ours after
/// all, and `read` returns `nil` so the model reads it instead. A partial read
/// would drop whatever the stray line said without telling anyone.
enum RecipeTextExportReader {
    private enum Section: String {
        case oils = "Oils"
        case additives = "Additives"
        case fragrances = "Fragrances"
    }

    private struct Row {
        var name: String
        var amount: Double
        var unit: String?
        var weight: Double?
        var weightUnit: String?
    }

    private static let collectionsPrefix = "Collections: "
    private static let rowSeparator = " — "
    private static let settingsSeparator = " · "

    /// A number as the exporter formats it: digits, possibly grouped and with a
    /// decimal part. `decimal(_:)` works out which separator is which.
    private static let number = #/\d(?:[\d\h.,']*\d)?/#

    /// `60%` or `60% (1 310,4 g)`.
    private static let percentageValue = #/(\d(?:[\d\h.,']*\d)?)\h*%(?:\h*\((\d(?:[\d\h.,']*\d)?)\h+(\S+)\))?/#
    private static let weightValue = #/(\d(?:[\d\h.,']*\d)?)\h+(\S+)/#
    /// `NaOH (99% pure)`.
    private static let singleLye = #/(NaOH|KOH) \((\d(?:[\d\h.,']*\d)?)% pure\)/#
    /// `KOH/NaOH 70/30 (90%/99% pure)`.
    private static let hybridLye =
        #/KOH\/NaOH (\d(?:[\d\h.,']*\d)?)\/(\d(?:[\d\h.,']*\d)?) \((\d(?:[\d\h.,']*\d)?)%\/(\d(?:[\d\h.,']*\d)?)% pure\)/#
    private static let percentRange = 0.0...100.0
    private static let superFatSegment = #/(\d(?:[\d\h.,']*\d)?)\h*% superfat/#
    private static let waterSegment = #/water (\d(?:[\d\h.,']*\d)?):1/#
    private static let failorSegment = #/Failor method \((.+)\)/#

    static func read(_ text: String) -> RecipeImportDraft? {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        guard let bodyStart = lines.firstIndex(where: isBodyLine) else { return nil }
        var draft = RecipeImportDraft()
        guard readHeader(lines[..<bodyStart], into: &draft),
              let body = readBody(lines[bodyStart...], into: &draft),
              let oils = body.rows[.oils], !oils.isEmpty,
              readOils(oils, into: &draft),
              let additives = ingredients(body.rows[.additives] ?? [], batchUnit: draft.batchUnit),
              let fragrances = ingredients(body.rows[.fragrances] ?? [], batchUnit: draft.batchUnit)
        else { return nil }
        draft.additives = additives
        draft.fragrances = fragrances
        draft.fragrancePercentage = fragranceLoad(body.rows[.fragrances] ?? [], oils: oils)

        if let settings = body.settings {
            guard readSettings(settings, into: &draft) else { return nil }
        } else {
            draft.recipeKind = .general
        }
        return draft
    }

    /// Sorts the lines after the header into section rows and the settings
    /// line, which comes last. `nil` for any line the exporter wouldn't have
    /// written where it stands.
    private static func readBody(
        _ lines: ArraySlice<String>,
        into draft: inout RecipeImportDraft
    ) -> (rows: [Section: [Row]], settings: String?)? {
        var rows: [Section: [Row]] = [:]
        var section: Section?
        var settings: String?
        for line in lines where !line.isEmpty {
            guard settings == nil else { return nil }
            if let heading = Section(rawValue: line) {
                guard rows[heading] == nil else { return nil }
                rows[heading] = []
                section = heading
            } else if line.hasPrefix(collectionsPrefix) {
                guard draft.collectionNames.isEmpty, section == nil else { return nil }
                draft.collectionNames = line.dropFirst(collectionsPrefix.count)
                    .components(separatedBy: ", ")
                    .filter { !$0.isEmpty }
            } else if let current = section, line.contains(rowSeparator) {
                guard let row = row(from: line, in: current) else { return nil }
                rows[current, default: []].append(row)
            } else if section != nil {
                settings = line
            } else {
                return nil
            }
        }
        return (rows, settings)
    }

    // MARK: - Header

    private static func isBodyLine(_ line: String) -> Bool {
        Section(rawValue: line) != nil || line.hasPrefix(collectionsPrefix)
    }

    /// The name, then the description on the lines after it. The description
    /// keeps its own line breaks; only the blank lines around it go.
    private static func readHeader(_ lines: ArraySlice<String>, into draft: inout RecipeImportDraft) -> Bool {
        let trimmed = Array(lines.drop { $0.isEmpty }.reversed().drop { $0.isEmpty }.reversed())
        guard let name = trimmed.first else { return false }
        draft.name = name
        draft.desc = trimmed.dropFirst().joined(separator: "\n")
        return true
    }

    // MARK: - Rows

    /// Split at the last separator: the value never contains one, and a name
    /// someone typed with a dash in it still reads whole.
    private static func row(from line: String, in section: Section) -> Row? {
        guard let split = line.range(of: rowSeparator, options: .backwards) else { return nil }
        let name = String(line[..<split.lowerBound])
        let value = String(line[split.upperBound...])
        guard !name.isEmpty else { return nil }

        if section == .oils, let match = value.wholeMatch(of: percentageValue) {
            guard let share = decimal(match.output.1) else { return nil }
            let weight = match.output.2.flatMap { decimal($0) }
            guard (match.output.2 == nil) == (weight == nil) else { return nil }
            return Row(name: name, amount: share, unit: "%", weight: weight, weightUnit: match.output.3.map(String.init))
        }
        return amountRow(name: name, value: value)
    }

    /// `12 g`, `1 % of oils (5,24 g)`, `50 % of fragrances (32,76 g)`. The unit
    /// is everything between the number and the bracket, since several contain
    /// spaces.
    private static func amountRow(name: String, value: String) -> Row? {
        guard let lead = value.prefixMatch(of: number), let amount = decimal(lead.output) else { return nil }
        var rest = value[lead.range.upperBound...].trimmingCharacters(in: .whitespaces)

        var weight: Double?
        var weightUnit: String?
        if rest.hasSuffix(")"), let open = rest.range(of: " (", options: .backwards) {
            let bracket = rest[open.upperBound..<rest.index(before: rest.endIndex)]
            guard let match = bracket.wholeMatch(of: weightValue),
                  let value = decimal(match.output.1)
            else { return nil }
            weight = value
            weightUnit = String(match.output.2)
            rest = String(rest[..<open.lowerBound])
        }
        guard !rest.isEmpty else { return nil }
        return Row(name: name, amount: amount, unit: rest, weight: weight, weightUnit: weightUnit)
    }

    // MARK: - Oils

    /// A percentage recipe states its shares, but rounded to one decimal; the
    /// bracketed weights carry two, so the shares are recomputed from them when
    /// they agree with what was printed. Their sum is the batch size, which the
    /// copy states nowhere else.
    private static func readOils(_ oils: [Row], into draft: inout RecipeImportDraft) -> Bool {
        if oils.allSatisfy({ $0.unit == "%" }) {
            draft.amountsArePercentages = true
            let weights = oils.compactMap(\.weight)
            let units = Set(oils.compactMap(\.weightUnit))
            let total = weights.reduce(0, +)
            // The exporter weighs every oil in one unit or none of them.
            guard weights.isEmpty || (weights.count == oils.count && units.count == 1) else { return false }
            let hasBatch = !weights.isEmpty && total > 0
            if hasBatch {
                guard let unit = units.first, RecipeImportDraft.supportedWeightUnits.contains(unit) else { return false }
                draft.batchSize = rounded(total)
                draft.batchUnit = unit
            }
            draft.oils = oils.map { row in
                let derived = hasBatch ? row.weight.map { rounded($0 / total * 100) } : nil
                let share = derived.flatMap { abs($0 - row.amount) <= 0.05 ? $0 : nil } ?? row.amount
                return ImportedIngredient(name: row.name, amount: share, unit: nil)
            }
            return true
        }

        let units = Set(oils.compactMap(\.unit))
        guard oils.allSatisfy({ $0.weight == nil }), units.count == 1, let unit = units.first,
              RecipeImportDraft.supportedWeightUnits.contains(unit)
        else { return false }
        draft.amountsArePercentages = false
        draft.batchUnit = unit
        draft.oils = oils.map { ImportedIngredient(name: $0.name, amount: $0.amount, unit: unit) }
        return true
    }

    /// Bracketed weights are the exporter's conversion, not an amount: they are
    /// checked for the batch's unit and otherwise left behind.
    private static func ingredients(_ rows: [Row], batchUnit: String?) -> [ImportedIngredient]? {
        if let batchUnit, rows.contains(where: { $0.weightUnit.map { $0 != batchUnit } ?? false }) { return nil }
        return rows.map { ImportedIngredient(name: $0.name, amount: $0.amount, unit: $0.unit) }
    }

    /// The fragrance load, which a `% of fragrances` recipe needs and the copy
    /// never prints: the blend's shares say how it splits, not how much of it
    /// there is. The bracketed weights do say how much, against the oils.
    private static func fragranceLoad(_ fragrances: [Row], oils: [Row]) -> Double? {
        let blend = FragranceUnit.percentOfFragrances.rawValue
        guard !fragrances.isEmpty, fragrances.allSatisfy({ $0.unit == blend }) else { return nil }

        let oilWeights = oils.compactMap { $0.unit == "%" ? $0.weight : $0.amount }
        let fragranceWeights = fragrances.compactMap(\.weight)
        guard oilWeights.count == oils.count, fragranceWeights.count == fragrances.count else { return nil }
        let oilTotal = oilWeights.reduce(0, +)
        guard oilTotal > 0 else { return nil }
        return rounded(fragranceWeights.reduce(0, +) / oilTotal * 100)
    }

    // MARK: - Settings

    /// `NaOH (99% pure) · 5% superfat · water 2,5:1 · Failor method (borax) ·
    /// cream soap method`, or `KOH/NaOH 70/30 (90%/99% pure)` in place of the lye.
    private static func readSettings(_ line: String, into draft: inout RecipeImportDraft) -> Bool {
        let segments = line.components(separatedBy: settingsSeparator)
        guard let lye = segments.first else { return false }

        if let match = lye.wholeMatch(of: singleLye) {
            draft.lyeType = String(match.output.1)
            draft.lyePurity = percentage(match.output.2)
            guard draft.lyePurity != nil else { return false }
        } else if let match = lye.wholeMatch(of: hybridLye) {
            draft.kohPercentage = percentage(match.output.1)
            draft.kohPurity = percentage(match.output.3)
            draft.naohPurity = percentage(match.output.4)
            guard draft.kohPercentage != nil, draft.kohPurity != nil, draft.naohPurity != nil else { return false }
        } else {
            return false
        }

        return segments.dropFirst().allSatisfy { readSegment($0, into: &draft) }
    }

    private static func readSegment(_ segment: String, into draft: inout RecipeImportDraft) -> Bool {
        if let match = segment.wholeMatch(of: superFatSegment) {
            draft.superFat = decimal(match.output.1)
            return draft.superFat != nil
        }
        if let match = segment.wholeMatch(of: waterSegment) {
            draft.waterParts = decimal(match.output.1)
            return draft.waterParts != nil
        }
        if let match = segment.wholeMatch(of: failorSegment) {
            let name = String(match.output.1)
            draft.cfmNeutralizer = CFMNeutralizer.allCases.first {
                $0.displayName.caseInsensitiveCompare(name) == .orderedSame
            }
            return draft.cfmNeutralizer != nil
        }
        switch segment {
        case "Failor method":
            draft.cfmNeutralizer = .boricAcid
        case "cream soap method":
            draft.isCreamSoap = true
        default:
            return false
        }
        return true
    }

    // MARK: - Numbers

    /// A number as the exporter formats it, in whatever region it was copied in.
    ///
    /// Grouping may be a space, a no-break space, a narrow no-break space, an
    /// apostrophe, a comma or a point, and the decimal a comma or a point. The
    /// exporter writes at most two decimals, so a lone separator followed by
    /// exactly three digits groups thousands and anything else is a decimal —
    /// which is what makes this independent of the reading device's locale.
    static func decimal(_ token: some StringProtocol) -> Double? {
        var digits = String(token).filter { !$0.isWhitespace && $0 != "'" }
        let commas = digits.count { $0 == "," }
        let points = digits.count { $0 == "." }

        if let lastComma = digits.lastIndex(of: ","), let lastPoint = digits.lastIndex(of: ".") {
            let grouping: Character = lastComma > lastPoint ? "." : ","
            digits = digits.filter { $0 != grouping }.replacingOccurrences(of: ",", with: ".")
        } else if commas + points > 1 {
            digits = digits.filter { $0 != "," && $0 != "." }
        } else if commas + points == 1, let mark = digits.firstIndex(where: { $0 == "," || $0 == "." }) {
            let fraction = digits[digits.index(after: mark)...]
            digits = fraction.count == 3
                ? digits.filter { $0 != "," && $0 != "." }
                : digits.replacingOccurrences(of: ",", with: ".")
        }
        return Double(digits)
    }

    private static func percentage(_ token: Substring) -> Double? {
        decimal(token).flatMap { percentRange.contains($0) ? $0 : nil }
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
