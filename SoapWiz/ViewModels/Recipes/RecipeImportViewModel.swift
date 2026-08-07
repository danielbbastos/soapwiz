import Foundation
import SwiftData

enum RecipeImportPhase: Equatable {
    case input
    case extracting
    case review
    case failed(RecipeImportError)
}

/// Drives the import flow: paste, extract, reconcile, review.
///
/// Nothing here touches the store. The only write the whole flow performs is
/// creating an `Ingredient` the user explicitly asks for, and that goes through
/// the normal ingredient form. The recipe itself isn't written until the user
/// presses Save on the recipe form afterwards.
@MainActor
@Observable
final class RecipeImportViewModel {
    var rawText: String = ""
    private(set) var phase: RecipeImportPhase = .input
    private(set) var sanitized: SanitizedRecipeText?
    private(set) var rows: [RecipeImportRow] = []
    private(set) var extractedDraft: RecipeImportDraft?

    /// The draft the review screen renders, empty before anything is extracted
    /// so the view has no optional to unwrap on every row.
    var reviewedDraft: RecipeImportDraft { extractedDraft ?? RecipeImportDraft() }

    @ObservationIgnored
    private let extractor: RecipeDraftExtracting?

    init(extractor: RecipeDraftExtracting? = nil) {
        self.extractor = extractor ?? Self.defaultExtractor()
    }

    private static func defaultExtractor() -> RecipeDraftExtracting? {
        #if DEBUG
        if RecipeImportDebugOverride.isEnabled { return CannedRecipeExtractor() }
        #endif
        guard #available(iOS 26, macOS 26, *) else { return nil }
        return FoundationModelsRecipeExtractor()
    }

    // MARK: - Derived state

    var canExtract: Bool {
        !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && phase != .extracting
    }

    var isExtracting: Bool { phase == .extracting }

    var unresolvedCount: Int { rows.count { !$0.isResolved } }

    var canConfirm: Bool {
        phase == .review && unresolvedCount == 0 && rows.contains { $0.role == .oil && $0.ingredient != nil }
    }

    /// The reason confirming isn't possible yet, or `nil` when it is. An import
    /// with no resolved oil would produce a recipe with nothing to saponify.
    var confirmBlocker: String? {
        guard phase == .review else { return nil }
        if unresolvedCount > 0 {
            return unresolvedCount == 1
                ? "One ingredient still needs to be created or skipped."
                : "\(unresolvedCount) ingredients still need to be created or skipped."
        }
        if !rows.contains(where: { $0.role == .oil && $0.ingredient != nil }) {
            return "A recipe needs at least one oil from your inventory."
        }
        return nil
    }

    var prepared: PreparedRecipeImport? {
        guard let extractedDraft, canConfirm else { return nil }
        return PreparedRecipeImport(draft: extractedDraft, rows: rows)
    }

    // MARK: - Extraction

    func extract(inventory: [Ingredient]) async {
        guard let extractor else {
            phase = .failed(.modelUnavailable(RecipeImportAvailability.current.explanation))
            return
        }
        phase = .extracting

        let names = inventory.map(\.name)
        var budget = RecipeTextSanitizer.defaultCharacterBudget
        var text = RecipeTextSanitizer.sanitize(rawText, knownIngredientNames: names, characterBudget: budget)
        sanitized = text

        guard !text.isEmpty else {
            phase = .failed(.nothingRecognised)
            return
        }

        do {
            try await runExtraction(extractor, on: text, inventory: inventory)
        } catch RecipeImportError.inputTooLong {
            // The character budget is an estimate — the model is the authority
            // on what fits. When it says no, halve the budget and try the
            // densest half rather than handing the failure straight to the user.
            budget /= 2
            text = RecipeTextSanitizer.sanitize(rawText, knownIngredientNames: names, characterBudget: budget)
            sanitized = text
            do {
                try await runExtraction(extractor, on: text, inventory: inventory)
            } catch {
                phase = .failed(importError(from: error))
            }
        } catch {
            phase = .failed(importError(from: error))
        }
    }

    private func runExtraction(
        _ extractor: RecipeDraftExtracting,
        on text: SanitizedRecipeText,
        inventory: [Ingredient]
    ) async throws {
        let extracted = try await extractor.extract(from: text)
        extractedDraft = extracted
        rows = RecipeIngredientReconciler.reconcile(extracted, against: inventory)
        phase = .review
    }

    private func importError(from error: Error) -> RecipeImportError {
        (error as? RecipeImportError) ?? .failed(error.localizedDescription)
    }

    // MARK: - Review actions

    func skip(_ rowID: UUID) {
        setResolution(.skipped, for: rowID)
    }

    func unskip(_ rowID: UUID) {
        setResolution(.unmatched, for: rowID)
    }

    /// Binds a row to the ingredient the user just created for it.
    ///
    /// The created ingredient is bound directly rather than looked up by name.
    /// The create sheet's completion runs synchronously right after the insert,
    /// before the parent's `@Query` has re-run, so re-matching against the
    /// inventory the view is holding would search a snapshot taken before the
    /// insert — and leave unmatched the one row the user just resolved.
    ///
    /// Other rows are re-resolved too: a recipe can name the same ingredient in
    /// two sections, and creating it once should settle both.
    func resolve(_ rowID: UUID, with ingredient: Ingredient, inventory: [Ingredient]) {
        setResolution(.matched(ingredient), for: rowID)
        rows = RecipeIngredientReconciler.resolveUnmatched(in: rows, against: inventory + [ingredient])
    }

    func returnToInput() {
        phase = .input
    }

    private func setResolution(_ resolution: RecipeImportResolution, for rowID: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[index].resolution = resolution
    }
}
