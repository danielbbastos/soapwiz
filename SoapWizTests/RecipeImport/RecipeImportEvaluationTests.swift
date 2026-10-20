import Testing
import Foundation
import FoundationModels
import UIKit
@testable import SoapWiz

private final class EvaluationBundleMarker {}

/// Runs the recipe texts and screenshots under `Evaluation/` through the real
/// on-device pipeline and reports how close the drafts come. A measurement, not
/// a gate: mismatches are printed, never failed. Skipped wherever the model
/// can't run, which is the simulator and CI.
///
/// Every report line starts with `EVAL `, so a device run can be filtered:
/// `xcodebuild test ... | grep '^EVAL '`.
@Suite("Recipe import evaluation")
@MainActor
struct RecipeImportEvaluationTests {

    /// Asks the model itself, not `RecipeImportAvailability`, which the debug
    /// stub launch argument can make report `.available` with no model behind it.
    ///
    /// The simulator is excluded explicitly: it can report the model available
    /// without being able to run it.
    nonisolated static var modelIsAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        guard #available(iOS 26, *) else { return false }
        guard case .available = SystemLanguageModel.default.availability else { return false }
        return true
        #endif
    }

    @Test(.enabled(if: RecipeImportEvaluationTests.modelIsAvailable, "needs the on-device language model"))
    func evaluate_RealPipeline_ReportsFieldAccuracy() async throws {
        guard #available(iOS 26, *) else { return }
        let bundle = Bundle(for: EvaluationBundleMarker.self)
        let cases = try RecipeImportEvaluation.loadCases(from: bundle)
        #expect(!cases.isEmpty)
        for evaluationCase in cases {
            _ = try RecipeImportEvaluation.resourceURL(try #require(evaluationCase.input ?? evaluationCase.image), in: bundle)
        }

        var results: [EvaluationCaseResult] = []
        var failures = 0
        for evaluationCase in cases {
            do {
                let text = try await Self.sourceText(for: evaluationCase, in: bundle)
                let draft = try await Self.read(text)
                results.append(EvaluationCaseResult(
                    caseID: evaluationCase.id,
                    fields: RecipeImportEvaluation.compare(evaluationCase.expected, with: draft),
                    draftSummary: RecipeImportEvaluation.compactDescription(of: draft),
                    error: nil
                ))
            } catch {
                failures += 1
                results.append(EvaluationCaseResult(
                    caseID: evaluationCase.id,
                    fields: RecipeImportEvaluation.allMissed(evaluationCase.expected),
                    draftSummary: nil,
                    error: String(describing: error)
                ))
            }
        }

        let report = RecipeImportEvaluation.report(for: results).joined(separator: "\n")
        print(report)
        try Self.record(report)

        #expect(failures < cases.count, "the extractor threw for every case")
    }

    /// What the import screen has in its box when the user taps Import: pasted
    /// text as it is, a photo after OCR and the same tidy the screen applies.
    private static func sourceText(for evaluationCase: RecipeImportEvaluationCase, in bundle: Bundle) async throws -> String {
        if let input = evaluationCase.input {
            let url = try RecipeImportEvaluation.resourceURL(input, in: bundle)
            return try String(contentsOf: url, encoding: .utf8)
        }
        guard let imageName = evaluationCase.image else {
            throw RecipeImportEvaluationError.badLine(0, "\(evaluationCase.id) has neither input nor image")
        }
        let url = try RecipeImportEvaluation.resourceURL(imageName, in: bundle)
        guard let image = UIImage(contentsOfFile: url.path) else {
            throw RecipeImportEvaluationError.missingResource(imageName)
        }
        let recognised = try await RecipeImageTextRecogniser.recogniseText(in: image)
        return RecipeTextSanitizer.tidiedForEditing(recognised)
    }

    @available(iOS 26, *)
    private static func read(_ rawText: String) async throws -> RecipeImportDraft {
        if let copy = RecipeTextExportReader.read(rawText) { return copy }
        return try await RecipeImportExtraction.run(
            rawText: rawText,
            knownIngredientNames: [],
            using: FoundationModelsRecipeExtractor()
        )
    }

    private static func record(_ report: String) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recipe-import-evaluation.txt")
        try report.write(to: url, atomically: true, encoding: .utf8)
        print("EVAL report written to \(url.path)")
        Attachment.record(report, named: "recipe-import-evaluation.txt")
    }
}
