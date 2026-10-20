import Foundation
@testable import SoapWiz

/// What a case expects of one field. Absent means the field is not scored;
/// null means the draft must hold no value for it.
enum ExpectedField<Value: Decodable & Equatable>: Equatable {
    case absent
    case null
    case value(Value)

    static func decode<Key: CodingKey>(
        _ type: Value.Type,
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> ExpectedField<Value> {
        guard container.contains(key) else { return .absent }
        if try container.decodeNil(forKey: key) { return .null }
        return .value(try container.decode(Value.self, forKey: key))
    }
}

struct ExpectedOil: Decodable, Equatable {
    let name: String
    let percent: Double
}

struct ExpectedRow: Decodable, Equatable {
    let name: String
    let amount: Double?
    let unit: String?
}

struct ExpectedRecipe: Decodable, Equatable {
    var oils: ExpectedField<[ExpectedOil]> = .absent
    var batchSize: ExpectedField<Double> = .absent
    var batchUnit: ExpectedField<String> = .absent
    var lyeType: ExpectedField<String> = .absent
    var lyePurity: ExpectedField<Double> = .absent
    var superFat: ExpectedField<Double> = .absent
    var waterParts: ExpectedField<Double> = .absent
    var fragrancePercentage: ExpectedField<Double> = .absent
    var additives: ExpectedField<[ExpectedRow]> = .absent
    var fragrances: ExpectedField<[ExpectedRow]> = .absent

    init() {}

    private enum CodingKeys: String, CodingKey {
        case oils, batchSize, batchUnit, lyeType, lyePurity, superFat
        case waterParts, fragrancePercentage, additives, fragrances
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        oils = try .decode([ExpectedOil].self, from: container, forKey: .oils)
        batchSize = try .decode(Double.self, from: container, forKey: .batchSize)
        batchUnit = try .decode(String.self, from: container, forKey: .batchUnit)
        lyeType = try .decode(String.self, from: container, forKey: .lyeType)
        lyePurity = try .decode(Double.self, from: container, forKey: .lyePurity)
        superFat = try .decode(Double.self, from: container, forKey: .superFat)
        waterParts = try .decode(Double.self, from: container, forKey: .waterParts)
        fragrancePercentage = try .decode(Double.self, from: container, forKey: .fragrancePercentage)
        additives = try .decode([ExpectedRow].self, from: container, forKey: .additives)
        fragrances = try .decode([ExpectedRow].self, from: container, forKey: .fragrances)
    }
}

struct RecipeImportEvaluationCase: Decodable {
    let id: String
    let source: String
    let origin: String
    let input: String?
    let image: String?
    let expected: ExpectedRecipe
    let notes: String?
}

struct EvaluationFieldResult: Equatable {
    let field: String
    let passed: Bool
    let expected: String
    let got: String
}

struct EvaluationCaseResult {
    let caseID: String
    let fields: [EvaluationFieldResult]
    let draftSummary: String?
    let error: String?

    var scored: Int { fields.count }
    var passed: Int { fields.filter(\.passed).count }
}

enum RecipeImportEvaluationError: Error, CustomStringConvertible {
    case missingResource(String)
    case badLine(Int, String)

    var description: String {
        switch self {
        case .missingResource(let name): "missing resource \(name)"
        case .badLine(let line, let reason): "cases.jsonl line \(line): \(reason)"
        }
    }
}

enum RecipeImportEvaluation {
    static let oilShareTolerance = 0.6
    static let waterPartsTolerance = 0.02
    static let relativeTolerance = 0.01
    static let absoluteTolerance = 0.01

    // MARK: - Loading

    static func resourceURL(_ fileName: String, in bundle: Bundle) throws -> URL {
        let url = URL(fileURLWithPath: fileName)
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        if let found = bundle.url(forResource: name, withExtension: ext) { return found }
        if let found = bundle.url(forResource: name, withExtension: ext, subdirectory: "Evaluation") { return found }
        throw RecipeImportEvaluationError.missingResource(fileName)
    }

    static func decodeCases(from data: Data) throws -> [RecipeImportEvaluationCase] {
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw RecipeImportEvaluationError.badLine(1, "not valid UTF-8")
        }
        let decoder = JSONDecoder()
        var cases: [RecipeImportEvaluationCase] = []
        for (index, line) in text.components(separatedBy: .newlines).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            do {
                cases.append(try decoder.decode(RecipeImportEvaluationCase.self, from: Data(trimmed.utf8)))
            } catch {
                throw RecipeImportEvaluationError.badLine(index + 1, String(describing: error))
            }
        }
        return cases
    }

    static func loadCases(from bundle: Bundle) throws -> [RecipeImportEvaluationCase] {
        let url = try resourceURL("cases.jsonl", in: bundle)
        return try decodeCases(from: try Data(contentsOf: url))
    }

    // MARK: - Normalisation

    static func words(in name: String) -> [String] {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    static func nameMatches(expected: String, draft: String) -> Bool {
        let draftWords = Set(words(in: draft))
        let expectedWords = words(in: expected)
        return !expectedWords.isEmpty && expectedWords.allSatisfy(draftWords.contains)
    }

    static func normalisedUnit(_ unit: String) -> String {
        let cleaned = unit.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". \t"))
        switch cleaned {
        case "oz", "ounce", "ounces": return "oz"
        case "g", "gram", "grams", "gr": return "g"
        case "tbsp", "tablespoon", "tablespoons": return "tbsp"
        case "tsp", "teaspoon", "teaspoons": return "tsp"
        case "lb", "lbs", "pound", "pounds": return "lb"
        default: return cleaned
        }
    }

    static func unitMatches(expected: String?, draft: String?) -> Bool {
        guard let expected else { return true }
        guard let draft else { return false }
        return normalisedUnit(expected) == normalisedUnit(draft)
    }

    static func numbersMatch(
        _ expected: Double,
        _ got: Double,
        absolute: Double = absoluteTolerance,
        relative: Double = relativeTolerance
    ) -> Bool {
        let difference = abs(expected - got)
        return difference <= absolute + 1e-9 || difference <= relative * abs(expected) + 1e-9
    }

    /// Each oil's share of the total, as the draft's own amounts if they are
    /// already percentages.
    static func oilShares(of draft: RecipeImportDraft) -> [Double] {
        if draft.amountsArePercentages { return draft.oils.map(\.amount) }
        let total = draft.oils.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return draft.oils.map { _ in 0 } }
        return draft.oils.map { $0.amount / total * 100 }
    }

    // MARK: - Comparison

    static func compare(_ expected: ExpectedRecipe, with draft: RecipeImportDraft) -> [EvaluationFieldResult] {
        var results: [EvaluationFieldResult] = []
        results += compareOils(expected.oils, draft)
        results += compareBatch(expected.batchSize, expected.batchUnit, draft)
        results += compareText("lyeType", expected.lyeType, draft.lyeType)
        results += compareNumber("lyePurity", expected.lyePurity, draft.lyePurity)
        results += compareNumber("superFat", expected.superFat, draft.superFat)
        results += compareNumber("waterParts", expected.waterParts, draft.waterParts, absolute: waterPartsTolerance)
        results += compareNumber("fragrancePercentage", expected.fragrancePercentage, draft.fragrancePercentage)
        results += compareRows("additives", expected.additives, draft.additives)
        results += compareRows("fragrances", expected.fragrances, draft.fragrances)
        return results
    }

    /// Every scored field counted as missed, for a case whose read threw.
    static func allMissed(_ expected: ExpectedRecipe) -> [EvaluationFieldResult] {
        compare(expected, with: RecipeImportDraft()).map {
            EvaluationFieldResult(field: $0.field, passed: false, expected: $0.expected, got: "no draft")
        }
    }

    static func format(_ value: Double?) -> String {
        guard let value else { return "none" }
        return value.formatted(.number.precision(.fractionLength(0...3)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }

    private static func compareNumber(
        _ field: String,
        _ expected: ExpectedField<Double>,
        _ got: Double?,
        absolute: Double = absoluteTolerance
    ) -> [EvaluationFieldResult] {
        switch expected {
        case .absent:
            return []
        case .null:
            return [EvaluationFieldResult(field: field, passed: got == nil, expected: "none", got: format(got))]
        case .value(let value):
            let passed = got.map { numbersMatch(value, $0, absolute: absolute) } ?? false
            return [EvaluationFieldResult(field: field, passed: passed, expected: format(value), got: format(got))]
        }
    }

    private static func compareText(
        _ field: String,
        _ expected: ExpectedField<String>,
        _ got: String?
    ) -> [EvaluationFieldResult] {
        switch expected {
        case .absent:
            return []
        case .null:
            return [EvaluationFieldResult(field: field, passed: got == nil, expected: "none", got: got ?? "none")]
        case .value(let value):
            let passed = got.map { $0.caseInsensitiveCompare(value) == .orderedSame } ?? false
            return [EvaluationFieldResult(field: field, passed: passed, expected: value, got: got ?? "none")]
        }
    }

    private static func compareBatch(
        _ size: ExpectedField<Double>,
        _ unit: ExpectedField<String>,
        _ draft: RecipeImportDraft
    ) -> [EvaluationFieldResult] {
        let gotSize: Double?
        if draft.amountsArePercentages {
            gotSize = draft.batchSize
        } else {
            let total = draft.oils.reduce(0) { $0 + $1.amount }
            gotSize = total > 0 ? total : nil
        }
        var results = compareNumber("batchSize", size, gotSize, absolute: 0)
        results += compareText("batchUnit", unit, draft.resolvedBatchUnit)
        return results
    }

    private static func compareOils(_ expected: ExpectedField<[ExpectedOil]>, _ draft: RecipeImportDraft) -> [EvaluationFieldResult] {
        let shares = oilShares(of: draft)
        let gotText = zip(draft.oils, shares).map { "\($0.name) \(format($1))" }.joined(separator: ", ")
        switch expected {
        case .absent:
            return []
        case .null:
            return [EvaluationFieldResult(
                field: "oils",
                passed: draft.oils.isEmpty,
                expected: "none",
                got: gotText.isEmpty ? "none" : gotText
            )]
        case .value(let oils):
            let expectedText = oils.map { "\($0.name) \(format($0.percent))" }.joined(separator: ", ")
            var used = Set<Int>()
            var allMatched = true
            for oil in oils {
                let candidates = draft.oils.indices.filter {
                    !used.contains($0) && nameMatches(expected: oil.name, draft: draft.oils[$0].name)
                }
                if let index = candidates.first(where: { abs(shares[$0] - oil.percent) <= oilShareTolerance + 1e-9 }) {
                    used.insert(index)
                } else {
                    allMatched = false
                }
            }
            let passed = allMatched && used.count == draft.oils.count
            return [EvaluationFieldResult(
                field: "oils",
                passed: passed,
                expected: expectedText.isEmpty ? "none" : expectedText,
                got: gotText.isEmpty ? "none" : gotText
            )]
        }
    }

    static func rowText(name: String, amount: Double?, unit: String?) -> String {
        let amountText = amount.map { " \(format($0))" } ?? ""
        return "\(name)\(amountText)\(unit.map { " \($0)" } ?? "")"
    }

    private static func compareRows(
        _ field: String,
        _ expected: ExpectedField<[ExpectedRow]>,
        _ draftRows: [ImportedIngredient]
    ) -> [EvaluationFieldResult] {
        let gotText = draftRows.map { rowText(name: $0.name, amount: $0.amount, unit: $0.unit) }.joined(separator: "; ")
        switch expected {
        case .absent:
            return []
        case .null:
            return [EvaluationFieldResult(
                field: field,
                passed: draftRows.isEmpty,
                expected: "none",
                got: gotText.isEmpty ? "none" : gotText
            )]
        case .value(let rows):
            let expectedText = rows.map { rowText(name: $0.name, amount: $0.amount, unit: $0.unit) }.joined(separator: "; ")
            var used = Set<Int>()
            var allMatched = true
            for row in rows {
                let match = draftRows.indices.first { index in
                    let candidate = draftRows[index]
                    return !used.contains(index)
                        && nameMatches(expected: row.name, draft: candidate.name)
                        && row.amount.map { numbersMatch($0, candidate.amount) } ?? true
                        && unitMatches(expected: row.unit, draft: candidate.unit)
                }
                if let match {
                    used.insert(match)
                } else {
                    allMatched = false
                }
            }
            let passed = allMatched && used.count == draftRows.count
            return [EvaluationFieldResult(
                field: field,
                passed: passed,
                expected: expectedText.isEmpty ? "none" : expectedText,
                got: gotText.isEmpty ? "none" : gotText
            )]
        }
    }
}
