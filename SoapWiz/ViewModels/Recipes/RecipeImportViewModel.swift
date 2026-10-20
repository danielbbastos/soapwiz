import Foundation
import SwiftData

/// An ingredient the user chose in place of one the file would create, and
/// the slug it carried when chosen: a merge can delete the row, and a deleted
/// row can't be asked.
private struct ManualMatch {
    let ingredient: Ingredient
    let slug: String
}

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
/// Three paths meet here. A `.soapwizrecipe` file, opened or pasted, is decoded
/// exactly and needs no language model at all. The readable text "Copy Recipe"
/// writes is read back by `RecipeTextExportReader`, also without the model.
/// Anything else is read by the on-device model. Which path applies is decided
/// by looking, not by asking the user to declare it.
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

    /// The recipe as it fills in during extraction, so the progress screen can
    /// show it growing rather than a bare spinner. `nil` except while a model
    /// read is in flight.
    private(set) var streamingDraft: RecipeImportDraft?

    /// What an exact payload would do, once one has been read.
    private(set) var transferPlan: RecipeTransferPlan?

    /// The user's choices by plan entry, so a plan rebuilt after a merge keeps
    /// them.
    @ObservationIgnored
    private var manualMatches: [Int: ManualMatch] = [:]

    /// The collections the last read was given, for matching the names a
    /// SoapWiz copy files its recipe under.
    @ObservationIgnored
    private var knownCollections: [RecipeCollection] = []

    /// The draft the review screen renders, empty before anything is extracted
    /// so the view has no optional to unwrap on every row.
    var reviewedDraft: RecipeImportDraft { extractedDraft ?? RecipeImportDraft() }
    /// Pasted text or a read under way: what a swipe mustn't close the sheet on.
    var hasChanges: Bool { !rawText.isEmpty || phase != .input }

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

    private let waitHints: RecipeImportWaitHints

    init(extractor: RecipeDraftExtracting? = nil, waitHints: RecipeImportWaitHints = RecipeImportWaitHints()) {
        self.waitHints = waitHints
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

    /// Whether the on-device model can be used at all. The exact path needs it
    /// for nothing, so it decides what the input screen offers rather than
    /// whether the screen exists.
    var canReadFreeText: Bool { modelIsUsable }

    /// A short line naming the current step, so an empty early snapshot still
    /// says something. Driven by how far `streamingDraft` has filled in, so it
    /// can't drift from what the progress screen actually shows.
    var extractionStatus: String {
        guard let streamingDraft, streamingDraft.hasAnyIngredient else {
            return waitHints.current ?? "Reading the text\u{2026}"
        }
        return streamingDraft.statesLyeSettings ? "Checking amounts\u{2026}" : "Finding ingredients\u{2026}"
    }

    var prepared: PreparedRecipeImport? {
        guard let extractedDraft, canConfirm else { return nil }
        let byName = Dictionary(
            knownCollections.map { ($0.name.lookupKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let matched = extractedDraft.collectionNames.compactMap { byName[$0.lookupKey] }
        return PreparedRecipeImport(draft: extractedDraft, rows: rows, collections: matched)
    }

    // MARK: - Exact payloads

    /// Reads a `.soapwizrecipe` file the user picked.
    ///
    /// A file has no readable text to fall back to, so every failure is
    /// reported rather than quietly retried another way.
    func openFile(
        at url: URL,
        inventory: [Ingredient],
        collections: [RecipeCollection],
        recipes: [Recipe]
    ) {
        let didScope = url.startAccessingSecurityScopedResource()
        defer { if didScope { url.stopAccessingSecurityScopedResource() } }

        do {
            let payload = try RecipeTransferDecoder.payload(fromFile: try Data(contentsOf: url))
            adopt(payload, inventory: inventory, collections: collections, recipes: recipes)
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
    func adoptPayloadFromText(
        inventory: [Ingredient],
        collections: [RecipeCollection],
        recipes: [Recipe] = []
    ) -> Bool {
        switch RecipeTransferDecoder.scan(text: rawText) {
        case .none:
            return false
        case .payload(let payload):
            adopt(payload, inventory: inventory, collections: collections, recipes: recipes)
            return true
        case .rejected(let error):
            phase = .failed(.failed(error.errorDescription ?? "That recipe couldn’t be read."))
            return true
        }
    }

    private func adopt(
        _ payload: RecipeTransferData,
        inventory: [Ingredient],
        collections: [RecipeCollection],
        recipes: [Recipe]
    ) {
        let plan = RecipeTransferPlan(
            payload: payload,
            inventory: inventory,
            collections: collections,
            recipes: recipes
        )
        guard !plan.isEmpty else {
            phase = .failed(.nothingRecognised)
            return
        }
        transferPlan = plan
        manualMatches = [:]
        phase = .exactReview
    }

    // MARK: - Extraction

    /// `context`, when given, is where the inventory is fetched again once the
    /// model has answered: see `finishExtraction`. The app always passes it; only
    /// tests that hold no store leave it out, and are matched against
    /// `inventory` as it was handed in.
    func extract(
        inventory: [Ingredient],
        collections: [RecipeCollection] = [],
        recipes: [Recipe] = [],
        context: ModelContext? = nil
    ) async {
        // Looked at before the model is consulted, and before availability is
        // even checked: an exact payload needs neither.
        guard !adoptPayloadFromText(
            inventory: inventory,
            collections: collections,
            recipes: recipes
        ) else { return }
        knownCollections = collections
        guard !adoptSoapWizCopy(inventory: inventory) else { return }

        guard let extractor, modelIsUsable else {
            phase = .failed(.modelUnavailable(RecipeImportAvailability.current.explanation))
            return
        }
        streamingDraft = nil
        phase = .extracting
        waitHints.start()
        defer { waitHints.stop() }

        do {
            let extracted = try await RecipeImportExtraction.run(
                rawText: rawText,
                knownIngredientNames: inventory.map(\.name),
                using: extractor,
                onSanitized: { sanitized = $0 },
                onRetry: { streamingDraft = nil },
                onPartial: { streamingDraft = $0 }
            )
            finishExtraction(extracted, inventory: inventory, context: context)
        } catch {
            streamingDraft = nil
            phase = .failed(importError(from: error))
        }
    }

    /// Reads SoapWiz's own "Copy Recipe" text straight into review, when that is
    /// what the box holds. The model misreads it — see `RecipeTextExportReader`.
    private func adoptSoapWizCopy(inventory: [Ingredient]) -> Bool {
        guard let draft = RecipeTextExportReader.read(rawText) else { return false }
        sanitized = nil
        extractedDraft = draft
        rows = RecipeIngredientReconciler.reconcile(draft, against: inventory, sectionsAreStated: true)
        phase = .review
        return true
    }

    /// Matches against the inventory fetched after the model answers, not the
    /// array captured before it was asked. The model takes seconds, and a sync
    /// in that time can run the duplicate merge: the captured array would then
    /// hold the copy it deleted, which traps when read (SW-209), and would lack
    /// the copy it kept when that one arrived during the wait — leaving the
    /// row unmatched and inviting a duplicate.
    private func finishExtraction(
        _ extracted: RecipeImportDraft,
        inventory: [Ingredient],
        context: ModelContext?
    ) {
        extractedDraft = extracted
        let current = context.map { (try? $0.fetch(FetchDescriptor<Ingredient>())) ?? [] } ?? inventory
        rows = RecipeIngredientReconciler.reconcile(extracted, against: current)
        streamingDraft = nil
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
        setResolution(RecipeIngredientReconciler.resolution(for: ingredient), for: rowID)
        rows = RecipeIngredientReconciler.resolveUnmatched(in: rows, against: inventory + [ingredient])
    }

    func returnToInput() {
        phase = .input
        transferPlan = nil
        manualMatches = [:]
    }

    /// Moves both review screens off rows the duplicate merge deleted. Each
    /// reads its matches on every render, and an import confirmed from them
    /// would write links to rows that no longer exist.
    ///
    /// The exact-copy plan is rebuilt rather than patched: it is worked out from
    /// the payload and the store alone, holds nothing the user decided, and
    /// matches collections and recipes as well as ingredients. The known
    /// collections are re-read for the same reason: `prepared` reads every
    /// name, and the merge collapses collections too.
    func resolveMergedRows(in context: ModelContext, filesIntoCollections: Bool = true) {
        rows = rows.map { $0.resolvedAfterMerge(in: context) }
        let collections = filesIntoCollections
            ? (try? context.fetch(FetchDescriptor<RecipeCollection>())) ?? []
            : []
        knownCollections = collections
        guard let plan = transferPlan else { return }
        var rebuilt = RecipeTransferPlan(
            payload: plan.payload,
            inventory: (try? context.fetch(FetchDescriptor<Ingredient>())) ?? [],
            collections: collections,
            recipes: (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        )
        // The user's own matches are decisions the payload and the store can't
        // reproduce. Followed onto the survivor of a merge, and dropped when
        // the ingredient has gone altogether.
        for (entryID, match) in manualMatches {
            guard let entry = rebuilt.ingredients.first(where: { $0.id == entryID }), entry.willBeCreated,
                  let live = LiveIngredient.resolve(match.ingredient, slug: match.slug, in: context)
            else {
                manualMatches[entryID] = nil
                continue
            }
            rebuilt = rebuilt.matching(entryID, to: live)
        }
        transferPlan = rebuilt
    }

    /// Matches an ingredient the file would create to one the user already has,
    /// so it takes no custom slot. Remembered so a rebuilt plan keeps it.
    func useExisting(_ entryID: Int, _ ingredient: Ingredient) {
        guard let plan = transferPlan else { return }
        manualMatches[entryID] = ManualMatch(ingredient: ingredient, slug: ingredient.librarySlug)
        transferPlan = plan.matching(entryID, to: ingredient)
    }

    /// Writes the reviewed payload into the library.
    ///
    /// Returns the recipes created, or `nil` if nothing was written: the file
    /// doesn't fit the free tier, or the save failed. The context is rolled
    /// back on failure so a half-written import — recipes without their line
    /// items, ingredients nothing references — never survives.
    func confirmExactImport(context: ModelContext, categories: [IngredientCategory], gate: FreeTierGate) -> [Recipe]? {
        guard let transferPlan else { return nil }
        guard gate.importFit(for: transferPlan, in: context).fits else { return nil }
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
