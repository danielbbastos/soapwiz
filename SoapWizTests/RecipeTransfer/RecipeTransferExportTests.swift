import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// What a shared file is called, and that what lands on disk is what the
/// importer will read back.
@MainActor
@Suite
struct RecipeTransferExportTests {

    private let fixture: RecipeTransferFixture

    init() throws {
        fixture = try RecipeTransferFixture()
    }

    // MARK: - Naming

    @Test func filename_OneRecipe_UsesItsOwnName() {
        let recipe = fixture.populatedRecipe(named: "Silky Butter Bar")

        #expect(RecipeTransferExport.filename(for: [recipe]) == "Silky Butter Bar")
    }

    /// Naming a multi-recipe file after the first recipe in it is a small lie
    /// the recipient only discovers after importing fifteen.
    @Test func filename_SeveralRecipes_UsesTheCount() {
        let recipes = (1...15).map { fixture.populatedRecipe(named: "Bar \($0)") }

        #expect(RecipeTransferExport.filename(for: recipes) == "15 SoapWiz Recipes")
    }

    @Test func filename_NameWithPathSeparators_RewritesThem() {
        let recipe = fixture.populatedRecipe(named: "Lemon/Lime: Summer Bar")

        let filename = RecipeTransferExport.filename(for: [recipe])

        #expect(!filename.contains("/"))
        #expect(!filename.contains(":"))
        #expect(filename == "Lemon-Lime- Summer Bar")
    }

    /// A leading dot would hide the file in every file browser it lands in.
    @Test func filename_NameStartingWithADot_DoesNotProduceAHiddenFile() {
        let recipe = fixture.populatedRecipe(named: ".secret bar")

        #expect(!RecipeTransferExport.filename(for: [recipe]).hasPrefix("."))
    }

    @Test func filename_UntitledRecipe_FallsBackToAUsableName() {
        let recipe = fixture.populatedRecipe(named: "   ")

        #expect(RecipeTransferExport.filename(for: [recipe]) == "SoapWiz Recipe")
    }

    // MARK: - File

    @Test func file_OneRecipe_WritesBytesThatDecodeBackUnderItsOwnName() throws {
        let recipe = fixture.populatedRecipe(named: "Round Trip Bar")

        let exported = try RecipeTransferExport.file(for: [recipe])
        defer { try? FileManager.default.removeItem(at: exported.url) }

        #expect(exported.url.lastPathComponent == "Round Trip Bar.soapwizrecipe")
        let decoded = try RecipeTransferDecoder.payload(fromFile: try Data(contentsOf: exported.url))
        #expect(decoded.recipes.count == 1)
        #expect(decoded.recipes.first?.name == "Round Trip Bar")
    }

    @Test func file_SeveralRecipes_WritesADecodableFileWithTheRightExtension() throws {
        let recipes = (1...3).map { fixture.populatedRecipe(named: "Bar \($0)") }
        fixture.context.processPendingChanges()

        let exported = try RecipeTransferExport.file(for: recipes)
        defer { try? FileManager.default.removeItem(at: exported.url) }

        #expect(exported.url.pathExtension == RecipeTransferExport.fileExtension)
        #expect(exported.url.lastPathComponent == "3 SoapWiz Recipes.soapwizrecipe")

        let decoded = try RecipeTransferDecoder.payload(fromFile: try Data(contentsOf: exported.url))
        #expect(decoded.recipes.map(\.name) == ["Bar 1", "Bar 2", "Bar 3"])
    }

    /// Sharing the same selection twice must present the sheet twice, which is
    /// why `ExportFile.id` is per-instance rather than derived from the URL.
    @Test func file_SameRecipesTwice_ProducesDistinctExportIdentities() throws {
        let recipe = fixture.populatedRecipe()

        let first = try RecipeTransferExport.file(for: [recipe])
        let second = try RecipeTransferExport.file(for: [recipe])
        defer {
            try? FileManager.default.removeItem(at: first.url)
            try? FileManager.default.removeItem(at: second.url)
        }

        #expect(first.id != second.id)
    }
}

/// Selection mode on the recipe list: what it gathers, and what it forgets.
@MainActor
@Suite
struct RecipeSelectionTests {

    private let fixture: RecipeTransferFixture
    private let model = RecipeListViewModel()

    init() throws {
        fixture = try RecipeTransferFixture()
    }

    @Test func beginSelecting_Always_StartsWithNothingSelected() {
        let recipe = fixture.populatedRecipe()
        model.beginSelecting()
        model.toggleSelection(of: recipe)
        model.endSelecting()

        model.beginSelecting()

        #expect(model.isSelecting)
        #expect(!model.hasSelection)
    }

    @Test func toggleSelection_Twice_Deselects() {
        let recipe = fixture.populatedRecipe()

        model.toggleSelection(of: recipe)
        #expect(model.isSelected(recipe))

        model.toggleSelection(of: recipe)
        #expect(!model.isSelected(recipe))
    }

    @Test func endSelecting_Always_ClearsTheSelection() {
        let recipe = fixture.populatedRecipe()
        model.beginSelecting()
        model.toggleSelection(of: recipe)

        model.endSelecting()

        #expect(!model.isSelecting)
        #expect(!model.hasSelection)
    }

    /// The exported file should read the way the screen did.
    @Test func selection_Always_KeepsTheListsOrderNotTheSetsOrder() {
        let recipes = (1...5).map { fixture.populatedRecipe(named: "Bar \($0)") }
        fixture.context.processPendingChanges()
        for recipe in recipes.reversed() {
            model.toggleSelection(of: recipe)
        }

        #expect(model.selection(from: recipes).map(\.name) == ["Bar 1", "Bar 2", "Bar 3", "Bar 4", "Bar 5"])
    }

    @Test func selection_RecipeNotInTheGivenList_IsExcluded() {
        let shown = fixture.populatedRecipe(named: "Shown")
        let filteredOut = fixture.populatedRecipe(named: "Filtered Out")
        fixture.context.processPendingChanges()
        model.toggleSelection(of: shown)
        model.toggleSelection(of: filteredOut)

        #expect(model.selection(from: [shown]).map(\.name) == ["Shown"])
    }

    @Test func exportButtonTitle_OneSelected_IsSingular() {
        model.toggleSelection(of: fixture.populatedRecipe())

        #expect(model.exportButtonTitle == "Share 1 Recipe")
    }

    @Test func exportButtonTitle_SeveralSelected_IsPlural() {
        let recipes = (1...3).map { fixture.populatedRecipe(named: "Bar \($0)") }
        fixture.context.processPendingChanges()
        recipes.forEach { model.toggleSelection(of: $0) }

        #expect(model.exportButtonTitle == "Share 3 Recipes")
    }

    @Test func exportSelection_WithSelection_ProducesAFileAndLeavesTheMode() throws {
        let recipes = (1...2).map { fixture.populatedRecipe(named: "Bar \($0)") }
        fixture.context.processPendingChanges()
        model.beginSelecting()
        recipes.forEach { model.toggleSelection(of: $0) }

        model.exportSelection(from: recipes)

        let exported = try #require(model.exportFile)
        defer { try? FileManager.default.removeItem(at: exported.url) }
        #expect(!model.isSelecting)
        #expect(model.exportErrorMessage == nil)

        let decoded = try RecipeTransferDecoder.payload(fromFile: try Data(contentsOf: exported.url))
        #expect(decoded.recipes.count == 2)
    }

    /// The title says how many are selected and the file has to hold that many.
    ///
    /// A collection chip tapped mid-selection changes which recipes the list
    /// shows. Exporting from the visible set instead of the selected one would
    /// quietly send fewer recipes than the user was told they had picked.
    @Test func exportSelection_SelectionFilteredOffScreen_StillExportsAllOfIt() throws {
        let recipes = (1...3).map { fixture.populatedRecipe(named: "Bar \($0)") }
        fixture.context.processPendingChanges()
        model.beginSelecting()
        recipes.forEach { model.toggleSelection(of: $0) }
        #expect(model.navigationTitle == "3 Selected")

        model.exportSelection(from: recipes)

        let exported = try #require(model.exportFile)
        defer { try? FileManager.default.removeItem(at: exported.url) }
        let decoded = try RecipeTransferDecoder.payload(fromFile: try Data(contentsOf: exported.url))
        #expect(decoded.recipes.count == 3)
    }

    @Test func navigationTitle_NotSelecting_IsTheScreenName() {
        #expect(model.navigationTitle == "Recipes")
    }

    @Test func navigationTitle_SelectingNothingYet_PromptsRatherThanCountsZero() {
        model.beginSelecting()

        #expect(model.navigationTitle == "Select Recipes")
    }

    @Test func navigationTitle_OneSelected_IsSingular() {
        model.beginSelecting()
        model.toggleSelection(of: fixture.populatedRecipe())

        #expect(model.navigationTitle == "1 Selected")
    }

    @Test func exportSelection_NothingSelected_DoesNothing() {
        model.beginSelecting()

        model.exportSelection(from: [fixture.populatedRecipe()])

        #expect(model.exportFile == nil)
        // Still in the mode: there is nothing to share yet, and dropping the
        // user out would read as the button having failed.
        #expect(model.isSelecting)
    }
}
