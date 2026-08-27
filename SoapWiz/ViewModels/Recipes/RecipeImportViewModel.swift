import Foundation
import SwiftData

enum RecipeImportPhase: Equatable {
    case input
    case extracting
    case review

    /// An exact payload was read and is waiting to be confirmed. Distinct from
    /// `.review` because the two screens show different things and confirming
    /// them does different things: this one writes to the library.
    case exactReview
    case failed(RecipeImportError)
}

/// Drives the import flow, whichever way a recipe arrives.
///
/// Two paths meet here. A `.soapwizrecipe` file, or text carrying the marker
/// "Copy Recipe" appends, is decoded exactly and needs no language model at all.
/// Anything else is read by the on-device model, as before. Which path applies
/// is decided by looking, not by asking the user to declare it.
///
/// Nothing here writes to the store. `RecipeTransferImporter` does that, from
/// the plan this builds, once the user confirms.
@MainActor
@Observable
final class RecipeImportViewModel {
    var rawText: String = ""
    private(set) var phase: RecipeImportPhase = .input
    private(set) var sanitized: SanitizedRecipeText?
    private(set) var rows: [RecipeImportRow] = []
    private(set) var extractedDraft: RecipeImportDraft?

    /// What an exact payload would do, once one has been read.
    private(set) var transferPlan: RecipeTransferPlan?

    /// The draft the review screen renders, empty before anything is extracted
    /// so the view has no optional to unwrap on every row.
    var reviewedDraft: RecipeImportDraft { extractedDraft ?? RecipeImportDraft() }

    @ObservationIgnored
    private let extractor: RecipeDraftExtracting?

    /// Whether the language model can actually run, as opposed to whether an
    /// extractor object exists.
    ///
    /// The two are not the same: `FoundationModelsRecipeExtractor` is
    /// constructed on any iOS 26 device and only fails when asked to do
    /// something, so a non-nil extractor says nothing about Apple Intelligence
    /// being switched on. `RecipeImportAvailability` is the honest answer, and
    /// the one the FAB used to gate the whole feature on.
    @ObservationIgnored
    private let modelIsUsable: Bool

    init(extractor: RecipeDraftExtracting? = nil) {
        if let extractor {
            self.extractor = extractor
            modelIsUsable = true
        } else {
            self.extractor = Self.defaultExtractor()
            modelIsUsable = RecipeImportAvailability.current.isAvailable
        }
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

    /// Whether the on-device model can be used at all. The exact path needs it
    /// for nothing, so it decides what the input screen offers rather than
    /// whether the screen exists.
    var canReadFreeText: Bool { modelIsUsable }

    /// Whether the text in the box is an exact payload.
    ///
    /// Lets the input screen say what will happen before the user commits to it:
    /// pasting a SoapWiz recipe is about to be read exactly, not interpreted.
    var textCarriesExactPayload: Bool {
        if case .payload = RecipeTransferMarker.scan(rawText) { return true }
        return false
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

    // MARK: - Exact payloads

    /// Reads a `.soapwizrecipe` file the user picked.
    ///
    /// A file has no readable text to fall back to, so every failure is
    /// reported rather than quietly retried another way.
    func openFile(
        at url: URL,
        inventory: [Ingredient],
        collections: [RecipeCollection]
    ) {
        let didScope = url.startAccessingSecurityScopedResource()
        defer { if didScope { url.stopAccessingSecurityScopedResource() } }

        do {
            let payload = try RecipeTransferDecoder.payload(fromFile: try Data(contentsOf: url))
            adopt(payload, inventory: inventory, collections: collections)
        } catch let error as RecipeTransferError {
            phase = .failed(.failed(error.errorDescription ?? "That file couldn’t be read."))
        } catch {
            phase = .failed(.failed("That file couldn’t be opened."))
        }
    }

    /// Whether the pasted text carries an exact payload, and adopting it if so.
    ///
    /// Returns `false` when there is nothing to adopt, so the caller falls
    /// through to the language model. A payload from a newer version is the one
    /// case that both returns `true` and refuses: the user has a real recipe in
    /// hand and needs to know an app update stands between them, rather than
    /// watching the model make a worse job of text it was never meant to read.
    @discardableResult
    func adoptPayloadFromText(inventory: [Ingredient], collections: [RecipeCollection]) -> Bool {
        switch RecipeTransferMarker.scan(rawText) {
        case .none:
            return false
        case .payload(let payload):
            adopt(payload, inventory: inventory, collections: collections)
            return true
        case .rejected(let error):
            phase = .failed(.failed(error.errorDescription ?? "That recipe couldn’t be read."))
            return true
        }
    }

    private func adopt(
        _ payload: RecipeTransferData,
        inventory: [Ingredient],
        collections: [RecipeCollection]
    ) {
        let plan = RecipeTransferPlan(payload: payload, inventory: inventory, collections: collections)
        guard !plan.isEmpty else {
            phase = .failed(.nothingRecognised)
            return
        }
        transferPlan = plan
        phase = .exactReview
    }

    // MARK: - Extraction

    func extract(inventory: [Ingredient], collections: [RecipeCollection] = []) async {
        // Looked at before the model is consulted, and before availability is
        // even checked: an exact payload needs neither.
        guard !adoptPayloadFromText(inventory: inventory, collections: collections) else { return }

        guard let extractor, modelIsUsable else {
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
        transferPlan = nil
    }

    /// Writes the reviewed payload into the library.
    ///
    /// Returns the recipes created, or `nil` if the save failed. The context is
    /// rolled back on failure so a half-written import — recipes without their
    /// line items, ingredients nothing references — never survives.
    func confirmExactImport(context: ModelContext, categories: [IngredientCategory]) -> [Recipe]? {
        guard let transferPlan else { return nil }
        let recipes = RecipeTransferImporter.apply(transferPlan, into: context, categories: categories)
        do {
            try context.save()
            return recipes
        } catch {
            context.rollback()
            phase = .failed(.failed("Those recipes couldn’t be saved. Please try again."))
            return nil
        }
    }

    private func setResolution(_ resolution: RecipeImportResolution, for rowID: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[index].resolution = resolution
    }
}
