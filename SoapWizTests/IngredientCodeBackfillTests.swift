import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The launch pass that fills the journal code on library rows installed by a
/// build that predates SW-156.
@Suite("Ingredient code backfill", .serialized)
@MainActor
struct IngredientCodeBackfillTests {

    private let olive = IngredientLibraryEntry.mock(slug: "olive-oil", name: "Olive Oil", code: "OLO")

    private var library: IngredientLibrary { IngredientLibrary(entries: [olive]) }

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    /// A library row saved before codes shipped carries the entry's slug and an
    /// empty code, which is exactly what the pass fills.
    private func libraryRow(code: String = "") -> Ingredient {
        let ingredient = Ingredient(name: "Olive Oil", unit: "g")
        ingredient.librarySlug = "olive-oil"
        ingredient.code = code
        return ingredient
    }

    @Test func fill_LibraryRowWithoutCode_TakesEntryCode() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let row = libraryRow()
        ctx.insert(row)
        try ctx.save()

        let filled = try IngredientCodeBackfill.fillMissingCodes(from: library, in: ctx)

        #expect(filled == 1)
        #expect(row.code == "OLO")
    }

    @Test func fill_UserTypedCode_IsLeftAlone() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let row = libraryRow(code: "MYX")
        ctx.insert(row)
        try ctx.save()

        let filled = try IngredientCodeBackfill.fillMissingCodes(from: library, in: ctx)

        #expect(filled == 0)
        #expect(row.code == "MYX")
    }

    @Test func fill_NonLibraryRow_IsIgnored() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let row = Ingredient(name: "My Own Thing", unit: "g")
        ctx.insert(row)
        try ctx.save()

        let filled = try IngredientCodeBackfill.fillMissingCodes(from: library, in: ctx)

        #expect(filled == 0)
        #expect(row.code.isEmpty)
    }

    @Test func fill_RowWhoseSlugIsNotInLibrary_IsIgnored() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let row = Ingredient(name: "Retired Oil", unit: "g")
        row.librarySlug = "retired-oil"
        ctx.insert(row)
        try ctx.save()

        let filled = try IngredientCodeBackfill.fillMissingCodes(from: library, in: ctx)

        #expect(filled == 0)
        #expect(row.code.isEmpty)
    }

    @Test func fill_EntryCodeAlreadyUsed_InstallsANonCollidingCode() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let mine = Ingredient(name: "My Own Thing", unit: "g")
        mine.code = "OLO"
        ctx.insert(mine)
        let row = libraryRow()
        ctx.insert(row)
        try ctx.save()

        let filled = try IngredientCodeBackfill.fillMissingCodes(from: library, in: ctx)

        #expect(filled == 1)
        #expect(!row.code.isEmpty)
        #expect(row.code.uppercased() != "OLO")
    }

    @Test func fill_SecondRun_ChangesNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        ctx.insert(libraryRow())
        try ctx.save()

        _ = try IngredientCodeBackfill.fillMissingCodes(from: library, in: ctx)
        let second = try IngredientCodeBackfill.fillMissingCodes(from: library, in: ctx)

        #expect(second == 0)
    }
}
