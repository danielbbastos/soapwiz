import Foundation
@testable import SoapWiz

extension RecipeImportEvaluation {
    static func compactDescription(of draft: RecipeImportDraft) -> String {
        func rows(_ rows: [ImportedIngredient]) -> String {
            rows.map { rowText(name: $0.name, amount: $0.amount, unit: $0.unit) }.joined(separator: "; ")
        }
        var parts = [
            "name=\(draft.name)",
            "percentages=\(draft.amountsArePercentages)",
            "batch=\(format(draft.batchSize)) \(draft.batchUnit ?? "none")",
            "lye=\(draft.lyeType ?? "none")",
            "purity=\(format(draft.lyePurity))",
            "superFat=\(format(draft.superFat))",
            "waterParts=\(format(draft.waterParts))",
            "fragrance%=\(format(draft.fragrancePercentage))"
        ]
        parts.append("oils=[\(rows(draft.oils))]")
        parts.append("additives=[\(rows(draft.additives))]")
        parts.append("fragrances=[\(rows(draft.fragrances))]")
        return parts.joined(separator: " | ")
    }

    static func report(for results: [EvaluationCaseResult]) -> [String] {
        var lines: [String] = []
        for result in results {
            lines.append("EVAL == \(result.caseID): \(result.passed)/\(result.scored)")
            if let error = result.error {
                lines.append("EVAL   ERROR \(error)")
            }
            for field in result.fields {
                if field.passed {
                    lines.append("EVAL   ✓ \(field.field): \(field.got)")
                } else {
                    lines.append("EVAL   ✗ \(field.field): expected \(field.expected), got \(field.got)")
                }
            }
            if let draftSummary = result.draftSummary {
                lines.append("EVAL   draft: \(draftSummary)")
            }
        }
        lines.append("EVAL == SUMMARY")
        for result in results {
            lines.append("EVAL   \(result.caseID): \(result.passed)/\(result.scored)\(result.error == nil ? "" : " (error)")")
        }
        let passed = results.reduce(0) { $0 + $1.passed }
        let scored = results.reduce(0) { $0 + $1.scored }
        let percent = scored == 0 ? 0 : Double(passed) / Double(scored) * 100
        lines.append("EVAL   OVERALL \(passed)/\(scored) (\(format(percent))%)")
        return lines
    }
}
