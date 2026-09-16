import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The edit sheet captures its `Ingredient` when it opens. If the duplicate
/// merge deletes that row while the sheet is still up, every field the form
/// writes lands on a detached model — silently, because `isDeleted` reads false
/// there — and the user's edit is gone with no error and no trace.
///
/// Unlike the purchase form this loses an edit rather than a child row, so there
/// is a safe fallback: resolve onto the survivor, and when there is none, write
/// where it would have written before.
@Suite("Ingredient form — stale references", .serialized)
@MainActor
struct IngredientFormStaleReferenceTests {

    /// The full schema: the merger fetches collections and settings, and `adopt`
    /// walks batch and recipe links.
    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration.inMemory(schema)]
        )
        return (container, container.mainContext)
    }

    private func uuid(_ index: Int) throws -> UUID {
        try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)"))
    }

    @discardableResult
    private func installed(_ index: Int, in ctx: ModelContext) throws -> Ingredient {
        let row = Ingredient(name: "Olive Butter", unit: IngredientUnit.grams.rawValue)
        row.librarySlug = "olive-butter"
        row.uuid = try uuid(index)
        ctx.insert(row)
        return row
    }

    private func ingredients(_ ctx: ModelContext) throws -> [Ingredient] {
        try ctx.fetch(FetchDescriptor<Ingredient>())
    }

    /// A row with no stored unit, so the form opens with nothing selected in the
    /// unit picker — the state `isValid` has to answer for without reading the
    /// row back.
    private func installedWithoutUnit(_ index: Int, in ctx: ModelContext) throws -> Ingredient {
        let row = Ingredient(name: "Olive Butter", unit: "")
        row.librarySlug = "olive-butter"
        row.uuid = try uuid(index)
        ctx.insert(row)
        return row
    }

    // MARK: - Editing across a merge

    /// The sheet was opened on the copy the merge then deleted. The edit has to
    /// land on the survivor, which is the row the user can still see.
    @Test func save_AfterMergeDeletedTheEditedRow_WritesToTheSurvivor() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installed(1, in: ctx)
        let captured = try installed(2, in: ctx)
        try ctx.save()
        let survivingUUID = keep.uuid

        let model = IngredientFormViewModel(ingredient: captured)
        try DuplicateMerger.mergeAll(in: ctx)
        #expect(captured.modelContext == nil)

        model.name = "Olive Butter Deodorised"
        model.code = "OBD"
        model.save(context: ctx)
        try ctx.save()

        let rows = try ingredients(ctx)
        #expect(rows.count == 1)
        #expect(rows.first?.uuid == survivingUUID)
        #expect(rows.first?.name == "Olive Butter Deodorised")
        #expect(rows.first?.code == "OBD")
    }

    /// The edit must survive a refetch, not merely be visible on an object the
    /// context happens to still hold.
    @Test func save_AfterMergeDeletedTheEditedRow_EditSurvivesARefetch() throws {
        let (container, ctx) = try makeContext()
        _ = container
        try installed(1, in: ctx)
        let captured = try installed(2, in: ctx)
        try ctx.save()

        let model = IngredientFormViewModel(ingredient: captured)
        try DuplicateMerger.mergeAll(in: ctx)

        model.name = "Renamed"
        model.save(context: ctx)
        try ctx.save()

        let refetched = try ctx.fetch(
            FetchDescriptor<Ingredient>(predicate: #Predicate { $0.librarySlug == "olive-butter" })
        )
        #expect(refetched.count == 1)
        #expect(refetched.first?.name == "Renamed")
    }

    /// The ordinary path, so the guards above cannot pass by writing nowhere.
    @Test func save_RowStillInTheStore_WritesToIt() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let row = try installed(1, in: ctx)
        try ctx.save()

        let model = IngredientFormViewModel(ingredient: row)
        model.name = "Edited"
        model.save(context: ctx)
        try ctx.save()

        #expect(row.name == "Edited")
        #expect(try ingredients(ctx).count == 1)
    }

    /// No survivor: the row was deleted outright rather than merged. The write
    /// falls back to the captured reference, which is what it did before — the
    /// point is that it must not crash or write onto an unrelated row.
    @Test func save_RowDeletedWithNoSurvivor_DoesNotCrashOrTouchOtherRows() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let other = try installed(1, in: ctx)
        let userRow = Ingredient(name: "Kokum Butter", unit: IngredientUnit.grams.rawValue)
        userRow.uuid = try uuid(2)
        ctx.insert(userRow)
        try ctx.save()

        let model = IngredientFormViewModel(ingredient: userRow)
        ctx.delete(userRow)
        try ctx.save()

        model.name = "Renamed"
        model.save(context: ctx)

        #expect(other.name == "Olive Butter")
        #expect(try ingredients(ctx).count == 1)
    }

    /// Creating has no captured row to go stale, and must keep returning the new
    /// ingredient for the caller to select.
    @Test func save_NewIngredient_IsUnaffectedAndStillReturned() throws {
        let (container, ctx) = try makeContext()
        _ = container

        let model = IngredientFormViewModel()
        model.name = "Shea Butter"
        model.selectedUnit = .grams
        let created = try #require(model.save(context: ctx))
        try ctx.save()

        #expect(created.name == "Shea Butter")
        #expect(created.librarySlug.isEmpty)
        #expect(try ingredients(ctx).count == 1)
    }

    /// A user-created row is never merged away, so the form must not go hunting
    /// for a survivor and rewrite an unrelated library row that shares its name.
    @Test func save_UserCreatedRowBesideALibraryTwin_EditsItsOwnRow() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let libraryRow = try installed(1, in: ctx)
        let userRow = Ingredient(name: "Olive Butter", unit: IngredientUnit.grams.rawValue)
        userRow.uuid = try uuid(2)
        ctx.insert(userRow)
        try ctx.save()

        let model = IngredientFormViewModel(ingredient: userRow)
        try DuplicateMerger.mergeAll(in: ctx)

        model.name = "My Olive Butter"
        model.save(context: ctx)
        try ctx.save()

        #expect(userRow.name == "My Olive Butter")
        #expect(libraryRow.name == "Olive Butter")
        #expect(try ingredients(ctx).count == 2)
    }

    // MARK: - Reading the form across a merge

    /// `isValid` drives the Save button's disabled state, so it runs on every
    /// render — including after the merge deleted the row the sheet was opened
    /// on. It answers from what `init` captured rather than reading the unit
    /// back off a reference that is no longer in the store.
    @Test func isValid_AfterMergeDeletedTheEditedRow_AnswersWithoutReadingIt() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installedWithoutUnit(1, in: ctx)
        let captured = try installedWithoutUnit(2, in: ctx)
        try ctx.save()

        let model = IngredientFormViewModel(ingredient: captured)
        #expect(model.selectedUnit == nil)

        try DuplicateMerger.mergeAll(in: ctx)
        #expect(captured.modelContext == nil)

        // Editing a row that never had a unit stays valid without one.
        #expect(model.isValid == true)
        #expect(keep.modelContext != nil)
    }

    /// The survivor is a different object from the copy the sheet captured, so
    /// an identity check alone would read its code as somebody else's and leave
    /// Save disabled on a duplicate of itself.
    @Test func codeHasDuplicate_AfterMergeDeletedTheEditedRow_DoesNotFlagTheSurvivor() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let keep = try installed(1, in: ctx)
        keep.code = "OLB"
        let captured = try installed(2, in: ctx)
        captured.code = "OLB"
        try ctx.save()

        let model = IngredientFormViewModel(ingredient: captured)
        try DuplicateMerger.mergeAll(in: ctx)

        #expect(model.codeHasDuplicate(among: try ingredients(ctx)) == false)
    }

    /// The exclusion is this row's slug, not a blanket pass: a different
    /// ingredient carrying the same code is still a clash.
    @Test func codeHasDuplicate_AnotherIngredientSharesTheCode_IsStillFlagged() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let edited = try installed(1, in: ctx)
        edited.code = "OLB"
        let other = Ingredient(name: "Kokum Butter", unit: IngredientUnit.grams.rawValue)
        other.uuid = try uuid(2)
        other.code = "OLB"
        ctx.insert(other)
        try ctx.save()

        let model = IngredientFormViewModel(ingredient: edited)

        #expect(model.codeHasDuplicate(among: try ingredients(ctx)) == true)
    }
}
