import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The import review screens match against the inventory once, when the recipe
/// is read, and render those matches until the user confirms. The duplicate
/// merge can delete a matched row in between — on a new device the first
/// CloudKit import does exactly that — and the next render reads it. SW-209.
@Suite("Recipe import — rows merged during review", .serialized)
@MainActor
struct RecipeImportDuplicateMergeTests {

    /// The full schema: `DuplicateMerger` fetches every lookup entity.
    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    private func uuid(_ index: Int) throws -> UUID {
        try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)"))
    }

    /// A library olive oil. Of two, the lowest `uuid` is the one the merge keeps.
    private func olive(_ index: Int, in ctx: ModelContext) throws -> Ingredient {
        let row = Ingredient(name: "Olive Oil", unit: IngredientUnit.grams.rawValue)
        row.librarySlug = "olive-oil"
        row.sapValue = 0.1345
        row.uuid = try uuid(index)
        ctx.insert(row)
        return row
    }

    private func gifts(_ index: Int, in ctx: ModelContext) throws -> RecipeCollection {
        let collection = RecipeCollection(name: "Gifts")
        collection.uuid = try uuid(index)
        ctx.insert(collection)
        return collection
    }

    private func row(matching ingredient: Ingredient) -> RecipeImportRow {
        RecipeImportRow(
            imported: ImportedIngredient(name: "Olive Oil", amount: 100, unit: nil),
            role: .oil,
            resolution: .matched(ingredient)
        )
    }

    // MARK: - Rows

    @Test func resolvedAfterMerge_MatchMergedAway_MovesOntoTheSurvivor() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try olive(1, in: ctx)
        let captured = try olive(2, in: ctx)
        try ctx.save()
        let row = row(matching: captured)

        try DuplicateMerger.mergeAll(in: ctx)
        let resolved = row.resolvedAfterMerge(in: ctx)

        #expect(resolved.ingredient === keep)
        #expect(resolved.id == row.id)
    }

    /// Nothing left to move onto: back to unmatched, for the user to create or
    /// skip, rather than left on a row the screen would read.
    @Test func resolvedAfterMerge_MatchDeletedWithNoSurvivor_GoesBackToUnmatched() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let userOil = Ingredient(name: "Olive Oil", unit: IngredientUnit.grams.rawValue)
        ctx.insert(userOil)
        try ctx.save()
        let row = row(matching: userOil)

        ctx.delete(userOil)
        try ctx.save()
        let resolved = row.resolvedAfterMerge(in: ctx)

        #expect(resolved.resolution == .unmatched)
    }

    @Test func resolvedAfterMerge_MatchStillStored_IsLeftAlone() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let oil = try olive(1, in: ctx)
        try ctx.save()

        let resolved = row(matching: oil).resolvedAfterMerge(in: ctx)

        #expect(resolved.ingredient === oil)
    }

    /// A row matched after the first read — the user created its ingredient on
    /// the review screen, or another row's creation matched it — takes its slug
    /// on assignment, not in `init`, and must still follow the merge.
    @Test func resolvedAfterMerge_RowMatchedAfterTheRead_MovesOntoTheSurvivor() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try olive(1, in: ctx)
        let captured = try olive(2, in: ctx)
        try ctx.save()
        let unmatched = RecipeImportRow(
            imported: ImportedIngredient(name: "Olive Oil", amount: 100, unit: nil),
            role: .oil,
            resolution: .unmatched
        )
        let matched = try #require(
            RecipeIngredientReconciler.resolveUnmatched(in: [unmatched], against: [captured]).first
        )
        #expect(matched.ingredient === captured)

        try DuplicateMerger.mergeAll(in: ctx)
        let resolved = matched.resolvedAfterMerge(in: ctx)

        #expect(resolved.ingredient === keep)
    }

    @Test func resolvedAfterMerge_SkippedRow_StaysSkipped() throws {
        let (container, ctx) = try makeContext()
        _ = container
        var row = row(matching: try olive(1, in: ctx))
        row.resolution = .skipped

        #expect(row.resolvedAfterMerge(in: ctx).resolution == .skipped)
    }

    // MARK: - Pasted-text review

    /// A SoapWiz copy read from text: its rows and the collections it files the
    /// recipe under were both matched before the merge.
    @Test func resolveMergedRows_TextReview_RowsAndCollectionsMoveOntoTheSurvivors() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keepOil = try olive(1, in: ctx)
        let capturedOil = try olive(2, in: ctx)
        let keepGifts = try gifts(3, in: ctx)
        let capturedGifts = try gifts(4, in: ctx)
        let recipe = Recipe(name: "Castile")
        ctx.insert(recipe)
        let line = RecipeIngredient(ingredient: capturedOil, percentage: 100, role: .oil)
        line.recipe = recipe
        ctx.insert(line)
        recipe.collections = [capturedGifts]
        try ctx.save()
        let model = RecipeImportViewModel(extractor: StubRecipeExtractor(draft: .mock()))
        model.rawText = RecipeTextExporter.text(for: recipe)
        await model.extract(inventory: [capturedOil], collections: [capturedGifts])
        #expect(model.rows.first?.ingredient === capturedOil)

        try DuplicateMerger.mergeAll(in: ctx)
        model.resolveMergedRows(in: ctx)

        #expect(model.rows.compactMap(\.ingredient) == [keepOil])
        let prepared = try #require(model.prepared)
        #expect(prepared.collections == [keepGifts])
    }

    /// The model takes seconds, and a joining device's first sync can land in
    /// that wait: it brings in the copy the merge keeps, and the merge deletes
    /// the one the screen handed in. Matching against what was handed in would
    /// read the deleted copy and miss the kept one.
    @Test func extract_MergeDuringTheModelsWait_MatchesTheSurvivor() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let captured = try olive(2, in: ctx)
        try ctx.save()
        let draft = RecipeImportDraft.mock(oils: [ImportedIngredient(name: "Olive Oil", amount: 100, unit: nil)])
        let stub = StreamingStubExtractor(partials: [draft], final: draft)
        var kept: Ingredient?
        stub.beforeFirstPartial = { @MainActor in
            kept = try? self.olive(1, in: ctx)
            try? ctx.save()
            try? DuplicateMerger.mergeAll(in: ctx)
        }
        let model = RecipeImportViewModel(extractor: stub)
        model.rawText = "Olive Oil 100%"

        await model.extract(inventory: [captured], context: ctx)

        let survivor = try #require(kept)
        #expect(captured.modelContext == nil)
        #expect(model.rows.compactMap(\.ingredient) == [survivor])
    }

    // MARK: - Exact-copy review

    /// The exact-copy plan holds the inventory row each incoming ingredient
    /// matched and the collection each name matched. Both are rebuilt onto the
    /// survivors, and confirming files the recipe under them.
    @Test func resolveMergedRows_ExactCopyPlan_MatchesMoveOntoTheSurvivors() throws {
        let source = try RecipeTransferFixture()
        let sent = source.recipe(named: "Shared Bar")
        source.addOil(source.oil("Olive Oil", slug: "olive-oil"), percentage: 100, to: sent)
        sent.collections = [source.collection("Gifts")]
        source.context.processPendingChanges()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("soapwizrecipe")
        try RecipeTransferEncoder.fileData(for: [sent]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let (container, ctx) = try makeContext()
        _ = container
        let keepOil = try olive(1, in: ctx)
        let capturedOil = try olive(2, in: ctx)
        let keepGifts = try gifts(3, in: ctx)
        let capturedGifts = try gifts(4, in: ctx)
        try ctx.save()
        let model = RecipeImportViewModel()
        model.openFile(at: url, inventory: [capturedOil], collections: [capturedGifts], recipes: [])
        #expect(model.transferPlan?.matchedIngredients.first?.existing === capturedOil)

        try DuplicateMerger.mergeAll(in: ctx)
        model.resolveMergedRows(in: ctx)

        let plan = try #require(model.transferPlan)
        #expect(plan.matchedIngredients.compactMap(\.existing) == [keepOil])
        #expect(plan.matchedCollections["Gifts"] === keepGifts)

        let categories = try ctx.fetch(FetchDescriptor<IngredientCategory>())
        let imported = try #require(model.confirmExactImport(context: ctx, categories: categories))
        let recipe = try #require(imported.first)
        #expect(recipe.ingredients.compactMap(\.ingredient) == [keepOil])
        #expect(recipe.collections == [keepGifts])
    }
}
