import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("InventoryImportMatcher", .serialized)
@MainActor
struct InventoryImportMatcherTests {

    private typealias Support = InventoryImportTestSupport

    private func existing(_ entry: InventoryImportEntry) -> Ingredient? {
        if case .existing(let match) = entry.resolution { return match.ingredient }
        return nil
    }

    private func firstLine(_ row: InventoryImportRow, inventory: [Ingredient] = []) throws -> InventoryImportLine {
        try #require(Support.plan([row], inventory: inventory).entries.first?.lines.first)
    }

    private func newIngredient(_ entry: InventoryImportEntry) -> InventoryImportNewIngredient? {
        if case .newIngredient(let new) = entry.resolution { return new }
        return nil
    }

    // MARK: - Matching

    @Test(arguments: ["OLIVE OIL", "olive oil", "  Olive  Oil "])
    func plan_NameVariations_MatchTheSameIngredient(_ written: String) throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let olive = Support.insertIngredient("Olive Oil", in: context)

        let plan = Support.plan([InventoryImportRow(name: written, quantity: 1)], inventory: [olive])

        #expect(existing(try #require(plan.entries.first)) === olive)
    }

    @Test func plan_DiacriticDifference_Matches() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let oliva = Support.insertIngredient("Óleo de Oliva", in: context)

        let plan = Support.plan([InventoryImportRow(name: "oleo de oliva", quantity: 1)], inventory: [oliva])

        #expect(existing(try #require(plan.entries.first)) === oliva)
    }

    @Test func plan_Alias_MatchesTheInstalledLibraryRow() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let almond = Support.insertIngredient("My Almond", slug: "sweet-almond-oil", in: context)

        let plan = Support.plan([InventoryImportRow(name: "Almond Oil", quantity: 100)], inventory: [almond])

        #expect(plan.entries.count == 1)
        #expect(existing(try #require(plan.entries.first)) === almond)
    }

    @Test func plan_NearMiss_IsNotMatched() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let olive = Support.insertIngredient("Olive Oil", slug: "olive-oil", in: context)

        let plan = Support.plan([InventoryImportRow(name: "Olive Pomace Oil", quantity: 100)], inventory: [olive])

        let entry = try #require(plan.entries.first)
        #expect(existing(entry) == nil)
        #expect(newIngredient(entry)?.name == "Olive Pomace Oil")
    }

    @Test func plan_UnknownName_IsANewIngredientWithoutLibraryEntry() throws {
        let plan = Support.plan([InventoryImportRow(name: "Zzyzx Butter", quantity: 5)], inventory: [])

        let entry = try #require(plan.entries.first)
        let new = try #require(newIngredient(entry))
        #expect(new.libraryEntry == nil)
        #expect(new.categoryName == nil)
    }

    @Test func plan_HiddenMatch_StillMatchesAndIsFlagged() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let hidden = Support.insertIngredient("Olive Oil", isHidden: true, in: context)

        let plan = Support.plan([InventoryImportRow(name: "Olive Oil", quantity: 10)], inventory: [hidden])

        let entry = try #require(plan.entries.first)
        #expect(existing(entry) === hidden)
        #expect(entry.isHidden)
        #expect(hidden.isHidden)
    }

    @Test func plan_ExistingIngredient_IsNotChanged() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let olive = Support.insertIngredient("Olive Oil", unit: .kilograms, density: 0.9, in: context)

        _ = Support.plan([InventoryImportRow(name: "Olive Oil", categoryName: "Other", unit: .grams, quantity: 10)], inventory: [olive])

        #expect(olive.unit == IngredientUnit.kilograms.rawValue)
        #expect(olive.density == 0.9)
        #expect(olive.category == nil)
        #expect(olive.purchases.isEmpty)
    }

    // MARK: - Grouping

    @Test func plan_SameNameNewIngredient_GroupsIntoOneEntry() throws {
        let rows = [
            InventoryImportRow(name: "Shea Butterr", quantity: 100),
            InventoryImportRow(name: "shea butterr", quantity: 200),
            InventoryImportRow(name: "Other Wax", quantity: 50)
        ]

        let plan = Support.plan(rows, inventory: [])

        #expect(plan.entries.count == 2)
        #expect(plan.entries[0].lines.count == 2)
        #expect(plan.entries[0].name == "Shea Butterr")
        #expect(plan.rowCount == 3)
    }

    @Test func plan_AliasesOfOneLibraryEntry_GroupIntoOneNewIngredient() throws {
        let rows = [
            InventoryImportRow(name: "Sweet Almond Oil", quantity: 100),
            InventoryImportRow(name: "Almond Oil", quantity: 100)
        ]

        let plan = Support.plan(rows, inventory: [])

        #expect(plan.entries.count == 1)
        #expect(plan.entries[0].lines.count == 2)
    }

    @Test func plan_SameNameMatchingExisting_GroupsLinesOnTheIngredient() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let olive = Support.insertIngredient("Olive Oil", in: context)

        let plan = Support.plan(
            [InventoryImportRow(name: "Olive Oil", quantity: 1), InventoryImportRow(name: "olive oil", quantity: 2)],
            inventory: [olive]
        )

        #expect(plan.entries.count == 1)
        #expect(plan.entries[0].lines.count == 2)
    }

    // MARK: - New ingredient defaults

    @Test func plan_NewIngredient_LibraryEntryProvidesUnitCategoryAndKeepsTheRowName() throws {
        let plan = Support.plan([InventoryImportRow(name: "almond oil", quantity: 100)], inventory: [])

        let entry = try #require(plan.entries.first)
        let new = try #require(newIngredient(entry))
        #expect(new.libraryEntry?.slug == "sweet-almond-oil")
        #expect(new.name == "almond oil")
        #expect(new.categoryName == IngredientCategory.Name.oils)
        #expect(new.unit == .grams)
    }

    @Test func plan_NewIngredient_RowCategoryBeatsLibraryCategory() throws {
        let plan = Support.plan([InventoryImportRow(name: "Sweet Almond Oil", categoryName: " Carriers ", quantity: 1)], inventory: [])

        #expect(newIngredient(try #require(plan.entries.first))?.categoryName == "Carriers")
    }

    @Test func plan_NewIngredient_RowUnitBeatsLibraryUnit() throws {
        let plan = Support.plan([InventoryImportRow(name: "Sweet Almond Oil", unit: .kilograms, quantity: 2)], inventory: [])

        let entry = try #require(plan.entries.first)
        #expect(newIngredient(entry)?.unit == .kilograms)
        #expect(entry.lines[0].quantity == 2)
    }

    @Test func plan_NewIngredientWithoutUnitOrEntry_FallsBackToGrams() throws {
        let plan = Support.plan([InventoryImportRow(name: "Zzyzx Butter", quantity: 7)], inventory: [])

        #expect(newIngredient(try #require(plan.entries.first))?.unit == .grams)
    }

    @Test func plan_GroupedNewIngredient_FirstRowUnitWinsAndLaterRowsConvert() throws {
        let rows = [
            InventoryImportRow(name: "Zzyzx Butter", quantity: 5),
            InventoryImportRow(name: "Zzyzx Butter", unit: .kilograms, quantity: 2),
            InventoryImportRow(name: "Zzyzx Butter", unit: .grams, quantity: 500)
        ]

        let entry = try #require(Support.plan(rows, inventory: []).entries.first)

        #expect(newIngredient(entry)?.unit == .kilograms)
        #expect(entry.lines[0].quantity == 5)
        #expect(entry.lines[1].quantity == 2)
        #expect(entry.lines[2].quantity == 0.5)
    }

    // MARK: - Quantities and units

    @Test func plan_NoQuantity_NewIngredientHasNoPurchaseQuantity() throws {
        let entry = try #require(Support.plan([InventoryImportRow(name: "Zzyzx Butter")], inventory: []).entries.first)

        #expect(entry.lines[0].quantity == nil)
        #expect(entry.lines[0].issues.isEmpty)
        #expect(entry.lines[0].isIncluded)
    }

    @Test func plan_NoQuantityOnMatch_IsBlockedAndSkipped() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let olive = Support.insertIngredient("Olive Oil", in: context)

        let rows = [InventoryImportRow(name: "Olive Oil"), InventoryImportRow(name: "olive oil", quantity: 0)]

        let plan = Support.plan(rows, inventory: [olive])

        let lines = plan.entries[0].lines
        #expect(lines.map(\.issues) == [[.nothingToAdd], [.nothingToAdd]])
        #expect(lines.allSatisfy { !$0.isImportable && !$0.isIncluded })
        #expect(plan.importableCount == 0)
        #expect(plan.skippedCount == 2)
    }

    @Test func plan_KilogramsIntoGrams_Converts() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let olive = Support.insertIngredient("Olive Oil", in: context)

        let line = try firstLine(InventoryImportRow(name: "Olive Oil", unit: .kilograms, quantity: 1.5), inventory: [olive])

        #expect(line.quantity == 1500)
        #expect(line.issues.isEmpty)
    }

    @Test func plan_NoRowUnit_QuantityIsTakenInTheIngredientsUnit() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let olive = Support.insertIngredient("Olive Oil", unit: .kilograms, in: context)

        let line = try firstLine(InventoryImportRow(name: "Olive Oil", quantity: 3), inventory: [olive])

        #expect(line.quantity == 3)
    }

    @Test func plan_MillilitersIntoGramsWithStoredDensity_ConvertsAndWarns() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let olive = Support.insertIngredient("Olive Oil", density: 0.9, in: context)

        let line = try firstLine(InventoryImportRow(name: "Olive Oil", unit: .milliliters, quantity: 100), inventory: [olive])

        #expect(abs(try #require(line.quantity) - 90) < 0.0001)
        #expect(line.issues == [.convertedViaDensity])
        #expect(line.isImportable)
    }

    @Test func plan_MillilitersIntoGramsWithoutDensity_BlocksOnlyThatRow() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let olive = Support.insertIngredient("Olive Oil", in: context)
        let rows = [
            InventoryImportRow(name: "Olive Oil", unit: .milliliters, quantity: 100),
            InventoryImportRow(name: "Olive Oil", unit: .kilograms, quantity: 1)
        ]

        let lines = try #require(Support.plan(rows, inventory: [olive]).entries.first?.lines)

        #expect(lines[0].issues == [.unitMismatch(rowUnit: "ml", ingredientUnit: "g")])
        #expect(!lines[0].isImportable)
        #expect(!lines[0].isIncluded)
        #expect(lines[0].quantity == nil)
        #expect(lines[1].isImportable)
        #expect(lines[1].quantity == 1000)
    }

    @Test func plan_CountAgainstWeight_BlocksOnlyThatRow() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let olive = Support.insertIngredient("Olive Oil", density: 0.9, in: context)
        let rows = [
            InventoryImportRow(name: "Olive Oil", unit: .units, quantity: 2),
            InventoryImportRow(name: "Olive Oil", unit: .grams, quantity: 50)
        ]

        let plan = Support.plan(rows, inventory: [olive])

        #expect(plan.entries[0].lines[0].issues == [.unitMismatch(rowUnit: "un", ingredientUnit: "g")])
        #expect(plan.entries[0].lines[1].isImportable)
        #expect(plan.importableCount == 1)
        #expect(plan.skippedCount == 1)
    }

    @Test func plan_WeightAgainstCountIngredient_Blocks() throws {
        let (container, context) = try Support.makeContext()
        _ = container
        let box = Support.insertIngredient("Soap Box", unit: .units, in: context)

        let line = try firstLine(InventoryImportRow(name: "Soap Box", unit: .grams, quantity: 5), inventory: [box])

        #expect(!line.isImportable)
    }

    @Test func plan_NewIngredientVolumeRowWithLibraryDensity_ConvertsAndWarns() throws {
        let rows = [
            InventoryImportRow(name: "Olive Oil", unit: .grams, quantity: 100),
            InventoryImportRow(name: "Olive Oil", unit: .milliliters, quantity: 100)
        ]
        let density = try #require(IngredientLibrary.entry(matching: "Olive Oil")?.density)

        let lines = try #require(Support.plan(rows, inventory: []).entries.first?.lines)

        #expect(lines[1].issues == [.convertedViaDensity])
        #expect(abs(try #require(lines[1].quantity) - 100 * density) < 0.0001)
    }

    // MARK: - Validation

    @Test func plan_NegativeQuantity_BlocksTheRow() throws {
        let line = try firstLine(InventoryImportRow(name: "Zzyzx Butter", quantity: -1))

        #expect(line.issues == [.invalidQuantity])
        #expect(!line.isIncluded)
    }

    @Test func plan_ZeroQuantity_IsTreatedAsNoQuantity() throws {
        let line = try firstLine(InventoryImportRow(name: "Zzyzx Butter", quantity: 0))

        #expect(line.quantity == nil)
        #expect(line.isImportable)
    }

    @Test func plan_MissingName_IsUnnamedAndBlocked() throws {
        let plan = Support.plan([InventoryImportRow(name: "   ", quantity: 1), InventoryImportRow(name: "Zzyzx Butter")], inventory: [])

        #expect(plan.entries.count == 1)
        #expect(plan.unnamed.count == 1)
        #expect(plan.unnamed[0].issues == [.missingName])
        #expect(!plan.unnamed[0].isIncluded)
        #expect(plan.importableCount == 1)
        #expect(plan.skippedCount == 1)
    }

    @Test func plan_SourceIssue_IsKeptAndBlockingOnesExcludeTheRow() throws {
        let row = InventoryImportRow(name: "Zzyzx Butter", quantity: 1, issues: [.invalidQuantity])

        let line = try #require(Support.plan([row], inventory: []).entries.first?.lines.first)

        #expect(line.issues == [.invalidQuantity])
        #expect(!line.isIncluded)
    }

    @Test func issue_Severities() {
        #expect(InventoryImportIssue.missingName.severity == .blocking)
        #expect(InventoryImportIssue.invalidQuantity.severity == .blocking)
        #expect(InventoryImportIssue.unitMismatch(rowUnit: "un", ingredientUnit: "g").severity == .blocking)
        #expect(InventoryImportIssue.convertedViaDensity.severity == .warning)
        #expect(InventoryImportIssue.nothingToAdd.severity == .blocking)
        #expect(!InventoryImportIssue.nothingToAdd.reason.isEmpty)
    }
}
